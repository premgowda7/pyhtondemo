# Runbook — troubleshooting

Always start from the user-facing symptom and walk the request path (architecture §1): **DNS → network → Kong → Service → Pod → dependency.**

```bash
kubectl -n argocd get applications                       # is GitOps healthy / synced?
kubectl -n orders get pods,svc,ingress,hpa,pdb
kubectl -n orders describe pod <pod>                     # Events: image pull, mount, probe failures
kubectl -n orders logs deploy/orders-api --tail=100      # JSON logs
kubectl -n kong logs deploy/kong-gateway --tail=100      # access log: status, upstream latency
```

## 1. 502/503 from Kong or "no Route matched"
| Check | Command | Meaning |
|---|---|---|
| Route exists | `kubectl -n orders get ingress` | `ingressClassName: kong`, path `/api` |
| Controller accepted it | `kubectl -n kong logs deploy/kong-controller \| grep -i error` | Translation errors (bad plugin config, missing service) |
| Endpoints ready | `kubectl -n orders get endpointslices -l kubernetes.io/service-name=orders-api` | Empty = all pods failing readiness → see §3 |
| NetworkPolicy | `kubectl -n orders get netpol` | Kong namespace must be named `kong` (label `kubernetes.io/metadata.name`) |

## 2. Pod stuck `ContainerCreating` — Key Vault CSI mount fails
`kubectl describe pod` → event `FailedMount ... secrets-store.csi.k8s.io`. Read the message:

| Message contains | Root cause | Fix |
|---|---|---|
| `AADSTS700213` / `No matching federated identity record` | Federated credential subject ≠ `system:serviceaccount:orders:<sa>`, or issuer URL mismatch | Compare `az identity federated-credential list` with namespace/SA name and `az aks show --query oidcIssuerProfile.issuerUrl` |
| `403 Forbidden` / `does not have secrets get permission` | Missing RBAC, or still propagating (up to ~10 min) | `az role assignment list --scope <kv-id>/secrets/db-password` |
| `no such host` / `i/o timeout` on `vault.azure.net` | Private DNS not linked to spoke, or PE missing | From a pod: `nslookup kv-...vault.azure.net` must return 10.10.9.x |
| `SecretNotFound` | Secret name typo | `keyVault.secrets` in values must equal the Key Vault secret name |
| `clientID` empty | `global.workloadIdentityClientIds` not synced | Run `scripts/sync-tf-outputs.sh`, commit |

## 3. Pods Running but not Ready (readiness 503)
`/readyz` checks the database. Logs show `readiness check failed: database unreachable`.
1. DNS: `kubectl -n orders run dbg --rm -it --image=mcr.microsoft.com/azurelinux/base/core:3.0 -- getent hosts <db-host>` → must be a private IP.
2. Network: NSG on `snet-private-endpoints` allows 5432 from VirtualNetwork; with firewall enabled, intra-VNet traffic must not be forced through it.
3. Auth: `password authentication failed` → the secret in Key Vault is out of sync with the server (someone reset it). Re-run `terraform apply` or update the secret, then wait ≤2 min for CSI rotation.

Liveness stays green while the DB is down **by design** (no restart storms). Fix the dependency instead of restarting pods.

## 4. `ImagePullBackOff`
| Cause | Check |
|---|---|
| Tag does not exist | `az acr repository show-tags -n <acr> --repository orders-api` |
| Kubelet lacks AcrPull | `az aks check-acr -g <rg> -n <aks> --acr <acr>.azurecr.io` |
| ACR private DNS | Both `<acr>.azurecr.io` and `<acr>.<region>.data.azurecr.io` must resolve privately (data endpoints enabled) |

## 5. Orders stay `PENDING`
- `kubectl -n orders logs deploy/worker | grep -E "batch failed|processed"`
- Metric `worker_batch_errors_total` rising = DB problem (§3). Flat with no logs = worker not running or `/healthz` stall → check restarts.

## 6. GitHub Actions
| Error | Fix |
|---|---|
| `AADSTS70021: No matching federated identity record` | Subject in the error must exist on the Entra app: `pull_request`, `ref:refs/heads/main`, `environment:dev`, `environment:dev-release` |
| Terraform `403` on Key Vault / ACR data plane or `dial tcp ... i/o timeout` | Runner is outside the private network → self-hosted runner (`PRIVATE_RUNNER_LABEL`) or temporary `management_ip_ranges` |
| `Error acquiring the state lock` | A previous run died. Confirm nothing is running, then `terraform force-unlock <id>` (from the runner) |
| promote job push rejected | Branch protection on `main` → allow `github-actions[bot]` to bypass, or change promote to open a PR |

## 7. ArgoCD
- App `OutOfSync` forever with `selfHeal` → something mutates the object in-cluster (HPA vs `replicas`: the chart omits `replicas` when HPA is on, keep it that way).
- `kong-config` / `dynakube` fail first sync with "no matches for kind" → CRDs not yet installed; retries resolve it once `kong` / `dynatrace-operator` are healthy.
- Private repo → add credentials: `argocd repo add https://github.com/premgowda7/pyhtondemo.git --github-app-id ...`

## 8. Dynatrace
- No pods instrumented → `kubectl -n dynatrace get dynakube` must be `Running`; pods started **before** the operator need a restart (`kubectl -n orders rollout restart deploy`).
- Token errors in operator logs → check Secret `dynakube` keys `apiToken`, `dataIngestToken` and token scopes per Dynatrace docs.

## Safe operations
- **Restart a service:** `kubectl -n orders rollout restart deploy/orders-api` (PDB + maxUnavailable 0 keep it available).
- **Roll back:** `git revert` the `chore(release)` commit → ArgoCD deploys the previous tag. Avoid `kubectl edit`; selfHeal will revert manual changes.
- **Rotate DB password:** `az postgres flexible-server update --admin-password` + update Key Vault secret `db-password` → pods pick it up within ~2 min on new connections. Never run `terraform destroy` on dev Postgres without a backup: `prevent_destroy` is set on purpose.
