#!/usr/bin/env bash
# Terraform outputs -> deploy/envs/dev/global.yaml (non-secret Helm values consumed by ArgoCD).
set -euo pipefail
cd "$(dirname "$0")/.."
terraform -chdir=infra/terraform/envs/dev output -json > /tmp/tf-outputs.json
python3 - <<'PY'
import json
o = {k: v["value"] for k, v in json.load(open("/tmp/tf-outputs.json")).items()}
out = f"""# GENERATED-BY: scripts/sync-tf-outputs.sh  (Terraform outputs -> Helm values). Safe to commit: no secrets.
global:
  environment: dev
  imageRegistry: {o['acr_login_server']}
  tenantId: {o['tenant_id']}
  keyVaultName: {o['key_vault_name']}
  db:
    host: {o['postgres_fqdn']}
    name: {o['postgres_database']}
    user: {o['postgres_admin_login']}
    sslmode: require
  workloadIdentityClientIds:
    orders-api: {o['orders_api_client_id']}
    worker: {o['worker_client_id']}
"""
open("deploy/envs/dev/global.yaml", "w").write(out)
print(out)
print(f"GitHub variables:\n  ACR_NAME={o['acr_name']}\n  ACR_LOGIN_SERVER={o['acr_login_server']}")
PY
rm -f /tmp/tf-outputs.json
echo ">> Review and commit deploy/envs/dev/global.yaml"
