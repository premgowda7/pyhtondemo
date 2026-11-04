# Architecture & flows

## 1. Request flow (user → database)

```
Browser / client (on-prem or via App Gateway WAF in the hub)
   │  HTTPS
   ▼
Kong proxy Service  type=LoadBalancer, INTERNAL, private IP in snet-ingress (10.10.8.0/24)
   │  NSG allows 80/443 only from the hub address space
   ▼
Kong Gateway pods (namespace kong)
   │  global plugins: correlation-id (X-Request-ID), prometheus, HSTS
   │  route plugins (orders-api): rate-limiting 300/min/IP, request-size 1 KB
   │  routing: /api → Service orders-api:80     / → Service web:80
   ▼
Service (ClusterIP) → Pod :8080         ← NetworkPolicy: only namespace "kong" (and "dynatrace" for scraping)
   │
   ▼  orders-api / worker → Postgres
DNS: psql-orders-dev-xxxx.postgres.database.azure.com
     → CNAME privatelink.postgres.database.azure.com  (Private DNS zone in hub, linked to spoke)
     → A 10.10.9.x  (Private Endpoint NIC in snet-private-endpoints)
   │  TCP 5432, TLS required (require_secure_transport=on)
   ▼
Azure Database for PostgreSQL Flexible Server (public network access disabled)
```

**Why the worker has no Service:** nothing calls it. Probes and Dynatrace scraping reach the pod IP directly.

## 2. Secret flow (Key Vault → pod), no secret ever in Git, CI or a Kubernetes Secret

```
Pod (serviceAccount: orders-api, label azure.workload.identity/use=true)
  └─ CSI volume (secrets-store.csi.k8s.io, SecretProviderClass orders-api-kv)
        1. kubelet asks the CSI driver to mount the volume, passing a projected SA token
           (audience api://AzureADTokenExchange, issuer = AKS OIDC issuer URL)
        2. Azure provider exchanges that token with Entra ID:
           federated credential on id-orders-dev-orders-api trusts exactly
           subject  system:serviceaccount:orders:orders-api
        3. Entra returns an access token for the managed identity
        4. GET https://kv-orders-dev-xxxx.vault.azure.net/secrets/db-password  (via Private Endpoint)
           RBAC: "Key Vault Secrets User" scoped to THIS secret only
        5. Written to tmpfs: /mnt/secrets-store/db-password (read-only mount)
  └─ App reads the file on every NEW DB connection (SQLAlchemy do_connect event)
        → rotation (CSI polls every 2 min) is picked up without a restart.
```

Breaking any one of these gives a specific, debuggable error — see runbook §2.

## 3. Deployment flow (commit → running pod)

```
git push (services/**) ──► release.yml
   1. OIDC: GitHub token (subject repo:premgowda7/pyhtondemo:environment:dev-release)
      → Entra federated credential → Azure access token (no client secret)
   2. az acr login (Entra token) → docker build → push <acr>/<svc>:<git-sha> (+ SBOM, provenance)
   3. Trivy gate on the pushed image
   4. yq sets image.tag=<git-sha> in deploy/envs/dev/<svc>.yaml → commit to main
ArgoCD (in cluster, polls GitHub every 3 min)
   5. Detects drift → helm template (chart + global.yaml + <svc>.yaml) → applies
   6. RollingUpdate maxSurge 1 / maxUnavailable 0; new pod must pass /readyz before old one is removed
   7. kubelet pulls from ACR via Private Endpoint using the kubelet identity (AcrPull)
```

CI never needs network access to the Kubernetes API, which is why a **private** cluster works with GitOps.

## 4. Infrastructure flow (Terraform)

```
PR touching infra/** ─► plan (OIDC, subject pull_request) ─► plan posted as PR comment
merge to main        ─► plan saved as artifact (1-day retention)
                     ─► "dev" environment approval ─► apply exactly that plan file
State: Azure Storage (Entra auth only, versioning + soft delete, CanNotDelete lock), blob lease = state lock
```

Creation order Terraform handles for you:
1. Resource groups → hub (VNet, DNS zones, optional firewall) → spoke (subnets, NSGs, UDR)
2. Peering + spoke DNS links
3. ACR / Key Vault / Postgres → their Private Endpoints (A records auto-registered via DNS zone groups)
4. Key Vault RBAC for the Terraform identity → 60 s propagation wait → `db-password` secret
5. AKS control-plane identity + Network Contributor (VNet) + Private DNS Zone Contributor (AKS zone) → AKS
6. AcrPull for kubelet identity; per-workload identities + federated credentials + secret-scoped RBAC

## 5. Observability

| Signal | Source | Where |
|---|---|---|
| Traces (PurePaths), process + host metrics | OneAgent (cloudNativeFullStack) auto-injected into pods | Dynatrace |
| Logs | stdout JSON (`ts, level, service, msg, order_id…`) collected by OneAgent | Dynatrace log viewer, fields searchable |
| App metrics | `/metrics` (Prometheus) via `metrics.dynatrace.com/*` annotations | Dynatrace (enable *Monitor annotated Prometheus exporters*) |
| Gateway metrics | Kong `prometheus` plugin, status port 8100 | Dynatrace |
| K8s events / workloads | ActiveGate `kubernetes-monitoring` | Dynatrace Kubernetes app |

Useful metrics: `http_request_duration_seconds` (orders-api latency by route/status), `orders_created_total`,
`orders_processed_total`, `worker_batch_errors_total`. Alert idea: `orders_created - orders_processed` growing for 10 min = worker backlog.

## 6. Network address plan

| Range | Use |
|---|---|
| 10.0.0.0/16 | Hub VNet: AzureFirewallSubnet /26, GatewaySubnet /27, snet-shared-services 10.0.2.0/24 |
| 10.10.0.0/16 | Spoke VNet: snet-aks-nodes 10.10.0.0/22, snet-ingress 10.10.8.0/24, snet-private-endpoints 10.10.9.0/24 |
| 192.168.0.0/16 | Pod CIDR (Azure CNI Overlay, not routable outside the cluster) |
| 172.16.0.0/16 | Kubernetes Service CIDR (DNS 172.16.0.10) |

Make sure none of these overlap your on-prem or other spoke ranges before the first apply. Changing them later means rebuilding the cluster.
