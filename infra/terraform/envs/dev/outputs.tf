# Consumed by scripts/sync-tf-outputs.sh -> deploy/envs/dev/global.yaml (no secrets here)
output "tenant_id" { value = data.azurerm_client_config.current.tenant_id }
output "resource_group_name" { value = azurerm_resource_group.spoke.name }
output "aks_name" { value = module.aks.name }
output "aks_oidc_issuer_url" { value = module.aks.oidc_issuer_url }
output "acr_name" { value = module.acr.name }
output "acr_login_server" { value = module.acr.login_server }
output "key_vault_name" { value = module.key_vault.name }
output "postgres_fqdn" { value = module.postgres.fqdn }
output "postgres_admin_login" { value = module.postgres.administrator_login }
output "postgres_database" { value = module.postgres.database_name }
output "orders_api_client_id" { value = module.wi_orders_api.client_id }
output "worker_client_id" { value = module.wi_worker.client_id }
output "ingress_subnet_name" { value = module.spoke.ingress_subnet_name }
output "hub_shared_subnet_id" { value = module.hub.shared_subnet_id }
