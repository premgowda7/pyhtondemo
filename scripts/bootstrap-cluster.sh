#!/usr/bin/env bash
# One-time cluster bootstrap: install ArgoCD, create the Dynatrace token secret, hand over to GitOps.
# The cluster is PRIVATE: run this from the hub (self-hosted runner / jumpbox / VPN).
# Prereqs: az, kubectl, kubelogin, helm; Key Vault secrets 'dynatrace-api-token' and
# 'dynatrace-data-ingest-token' created manually (never in Git).
set -euo pipefail
cd "$(dirname "$0")/.."

RG=$(terraform -chdir=infra/terraform/envs/dev output -raw resource_group_name)
AKS=$(terraform -chdir=infra/terraform/envs/dev output -raw aks_name)
KV=$(terraform -chdir=infra/terraform/envs/dev output -raw key_vault_name)
ARGOCD_CHART_VERSION=10.12.0

echo ">> kubeconfig (Entra ID; local accounts are disabled)"
az aks get-credentials -g "$RG" -n "$AKS" --overwrite-existing
kubelogin convert-kubeconfig -l azurecli

echo ">> ArgoCD $ARGOCD_CHART_VERSION"
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null && helm repo update argo >/dev/null
helm upgrade --install argocd argo/argo-cd --version "$ARGOCD_CHART_VERSION" \
  -n argocd --create-namespace -f deploy/argocd/bootstrap/argocd-values.yaml --wait

echo ">> Dynatrace token secret (from Key Vault, piped - never written to disk)"
kubectl create namespace dynatrace --dry-run=client -o yaml | kubectl apply -f -
kubectl -n dynatrace create secret generic dynakube \
  --from-literal=apiToken="$(az keyvault secret show --vault-name "$KV" -n dynatrace-api-token --query value -o tsv)" \
  --from-literal=dataIngestToken="$(az keyvault secret show --vault-name "$KV" -n dynatrace-data-ingest-token --query value -o tsv)" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ">> Hand over to GitOps"
kubectl apply -f deploy/argocd/bootstrap/repositories.yaml
kubectl apply -f deploy/argocd/bootstrap/root-app.yaml

cat <<OUT
Done. ArgoCD now reconciles everything from Git.
  UI:       kubectl -n argocd port-forward svc/argocd-server 8080:443   -> https://localhost:8080
  Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
  Status:   kubectl -n argocd get applications
If the repo is private, add a repo credential (GitHub App or deploy key) in ArgoCD first.
OUT
