#!/usr/bin/env bash
# One-time setup (run by a subscription Owner, locally):
#   1. Terraform state storage (Entra ID auth only - shared keys disabled)
#   2. Entra app + federated credentials for GitHub Actions OIDC (no client secret)
#   3. Role assignments for the pipeline identity
# Usage: GITHUB_REPO=premgowda7/pyhtondemo LOCATION=centralindia ./scripts/bootstrap-azure.sh
set -euo pipefail

: "${GITHUB_REPO:?set GITHUB_REPO=owner/repo}"
LOCATION="${LOCATION:-centralindia}"
STATE_RG="${STATE_RG:-rg-orders-tfstate}"
STATE_SA="${STATE_SA:-stordertfstate$RANDOM}"
APP_NAME="${APP_NAME:-gh-orders-platform-deployer}"

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
echo ">> Subscription: $SUBSCRIPTION_ID  Tenant: $TENANT_ID"
read -r -p "Continue in this subscription? [y/N] " ok; [[ "$ok" == "y" ]] || exit 1

echo ">> 1/3 Terraform state storage"
az group create -n "$STATE_RG" -l "$LOCATION" -o none
az storage account create -n "$STATE_SA" -g "$STATE_RG" -l "$LOCATION" \
  --sku Standard_ZRS --kind StorageV2 --min-tls-version TLS1_2 \
  --allow-blob-public-access false --allow-shared-key-access false \
  --https-only true -o none
az storage account blob-service-properties update -n "$STATE_SA" -g "$STATE_RG" \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 30 \
  --enable-container-delete-retention true --container-delete-retention-days 30 -o none
SA_ID=$(az storage account show -n "$STATE_SA" -g "$STATE_RG" --query id -o tsv)
az lock create -n do-not-delete --lock-type CanNotDelete --resource "$SA_ID" -o none

ME=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee-object-id "$ME" --assignee-principal-type User \
  --role "Storage Blob Data Contributor" --scope "$SA_ID" -o none
echo "   waiting for RBAC propagation..."; sleep 45
az storage container create -n tfstate --account-name "$STATE_SA" --auth-mode login -o none

echo ">> 2/3 Entra app + GitHub OIDC federated credentials"
APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)
if [[ -z "$APP_ID" ]]; then
  APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
  az ad sp create --id "$APP_ID" -o none
fi
SP_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv)

# Each subject is one trusted GitHub context. Nothing else in GitHub can obtain a token.
for subject in \
  "repo:${GITHUB_REPO}:pull_request" \
  "repo:${GITHUB_REPO}:ref:refs/heads/main" \
  "repo:${GITHUB_REPO}:environment:dev" \
  "repo:${GITHUB_REPO}:environment:dev-release"; do
  name=$(echo "$subject" | sed 's/[^a-zA-Z0-9-]/-/g' | cut -c1-120)
  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\": \"$name\", \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"$subject\", \"audiences\": [\"api://AzureADTokenExchange\"]}" -o none 2>/dev/null \
    || echo "   (exists) $subject"
done

echo ">> 3/3 Role assignments for the pipeline identity"
# Contributor: create resources. RBAC Administrator: Terraform creates role assignments
# (AcrPull, Key Vault Secrets User...). Tighten with an ABAC condition limiting assignable roles in prod.
az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
  --role Contributor --scope "/subscriptions/$SUBSCRIPTION_ID" -o none
az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
  --role "Role Based Access Control Administrator" --scope "/subscriptions/$SUBSCRIPTION_ID" -o none
az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope "$SA_ID" -o none

sed -i "s/^storage_account_name = .*/storage_account_name = \"$STATE_SA\"/" infra/terraform/envs/dev/backend.hcl

cat <<OUT

Done. Next:
  1) Set GitHub repository variables (Settings > Secrets and variables > Actions > Variables):
       gh variable set AZURE_CLIENT_ID       --body $APP_ID       --repo $GITHUB_REPO
       gh variable set AZURE_TENANT_ID       --body $TENANT_ID    --repo $GITHUB_REPO
       gh variable set AZURE_SUBSCRIPTION_ID --body $SUBSCRIPTION_ID --repo $GITHUB_REPO
  2) Create GitHub environments 'dev' (add Required reviewers) and 'dev-release'.
  3) Commit infra/terraform/envs/dev/backend.hcl (storage account name updated).
  4) After the first terraform apply: ./scripts/sync-tf-outputs.sh, then set ACR_NAME / ACR_LOGIN_SERVER variables.
  5) After the first terraform apply, grant AcrPush to the pipeline:
       az role assignment create --assignee-object-id $SP_ID --assignee-principal-type ServicePrincipal \\
         --role AcrPush --scope \$(az acr show -n <acr-name> --query id -o tsv)
OUT
