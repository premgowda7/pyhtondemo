data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

locals {
  name   = "${var.project}-${var.environment}"
  suffix = random_string.suffix.result
  tags = merge(var.tags, {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
  })

  private_dns_zones = {
    acr      = "privatelink.azurecr.io"
    kv       = "privatelink.vaultcore.azure.net"
    postgres = "privatelink.postgres.database.azure.com"
    aks      = "privatelink.${var.location}.azmk8s.io"
  }

  # Egress needed by platform components when the firewall is enabled.
  allowed_egress_fqdns = [
    "github.com", "*.githubusercontent.com",                       # ArgoCD -> Git
    "charts.konghq.com", "registry-1.docker.io", "auth.docker.io", # Kong chart + image
    "production.cloudflare.docker.com",
    "quay.io", "*.quay.io",               # ArgoCD images
    "public.ecr.aws", "*.cloudfront.net", # Dynatrace operator images
    "*.live.dynatrace.com",               # Dynatrace SaaS
    "login.microsoftonline.com", "*.vault.azure.net",
  ]
}

# ---------------------------------------------------------------- resource groups
resource "azurerm_resource_group" "hub" {
  name     = "rg-${var.project}-hub-${var.environment}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "spoke" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------- networking (hub-spoke)
module "hub" {
  source               = "../../modules/hub-network"
  name                 = "${var.project}-hub-${var.environment}"
  location             = var.location
  resource_group_name  = azurerm_resource_group.hub.name
  address_space        = var.hub_address_space
  private_dns_zones    = values(local.private_dns_zones)
  firewall_enabled     = var.firewall_enabled
  egress_source_cidrs  = [var.spoke_address_space]
  allowed_egress_fqdns = local.allowed_egress_fqdns
  tags                 = local.tags
}

module "spoke" {
  source                = "../../modules/spoke-network"
  name                  = local.name
  location              = var.location
  resource_group_name   = azurerm_resource_group.spoke.name
  address_space         = var.spoke_address_space
  firewall_private_ip   = module.hub.firewall_private_ip
  ingress_allowed_cidrs = [var.hub_address_space]
  tags                  = local.tags
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "peer-hub-to-${local.name}"
  resource_group_name       = azurerm_resource_group.hub.name
  virtual_network_name      = module.hub.vnet_name
  remote_virtual_network_id = module.spoke.vnet_id
  allow_forwarded_traffic   = true
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-${local.name}-to-hub"
  resource_group_name       = azurerm_resource_group.spoke.name
  virtual_network_name      = module.spoke.vnet_name
  remote_virtual_network_id = module.hub.vnet_id
  allow_forwarded_traffic   = true
}

# Spoke resolves privatelink.* names through the hub's zones.
resource "azurerm_private_dns_zone_virtual_network_link" "spoke" {
  for_each             = local.private_dns_zones
  name                 = "link-${module.spoke.vnet_name}"
  private_dns_zone_id  = module.hub.private_dns_zone_ids[each.value]
  virtual_network_id   = module.spoke.vnet_id
  registration_enabled = false
  tags                 = local.tags
  depends_on           = [module.hub]
}

# ---------------------------------------------------------------- data services (private only)
module "acr" {
  source              = "../../modules/acr"
  name                = "acr${var.project}${var.environment}${local.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.spoke.name
  allowed_ip_ranges   = var.management_ip_ranges
  tags                = local.tags
}

module "key_vault" {
  source              = "../../modules/key-vault"
  name                = "kv-${local.name}-${local.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.spoke.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  allowed_ip_ranges   = var.management_ip_ranges
  tags                = local.tags
}

module "postgres" {
  source              = "../../modules/postgres"
  name                = "psql-${local.name}-${local.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.spoke.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.tags
}

module "pe_acr" {
  source              = "../../modules/private-endpoint"
  name                = module.acr.name
  location            = var.location
  resource_group_name = azurerm_resource_group.spoke.name
  subnet_id           = module.spoke.private_endpoints_subnet_id
  resource_id         = module.acr.id
  subresource_name    = "registry"
  private_dns_zone_id = module.hub.private_dns_zone_ids[local.private_dns_zones.acr]
  tags                = local.tags
}

module "pe_kv" {
  source              = "../../modules/private-endpoint"
  name                = module.key_vault.name
  location            = var.location
  resource_group_name = azurerm_resource_group.spoke.name
  subnet_id           = module.spoke.private_endpoints_subnet_id
  resource_id         = module.key_vault.id
  subresource_name    = "vault"
  private_dns_zone_id = module.hub.private_dns_zone_ids[local.private_dns_zones.kv]
  tags                = local.tags
}

module "pe_postgres" {
  source              = "../../modules/private-endpoint"
  name                = "psql-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.spoke.name
  subnet_id           = module.spoke.private_endpoints_subnet_id
  resource_id         = module.postgres.id
  subresource_name    = "postgresqlServer"
  private_dns_zone_id = module.hub.private_dns_zone_ids[local.private_dns_zones.postgres]
  tags                = local.tags
}

# ---------------------------------------------------------------- secrets
# The identity running Terraform writes secrets (data-plane RBAC).
resource "azurerm_role_assignment" "tf_kv_secrets_officer" {
  scope                = module.key_vault.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "kv_rbac_propagation" {
  create_duration = "60s" # Azure RBAC is eventually consistent
  depends_on      = [azurerm_role_assignment.tf_kv_secrets_officer, module.pe_kv]
}

# NOTE: the generated password is also stored in Terraform state -> state must be private + encrypted (it is: Entra-only storage).
resource "azurerm_key_vault_secret" "db_password" {
  name         = "db-password"
  value        = module.postgres.administrator_password
  key_vault_id = module.key_vault.id
  content_type = "password"
  tags         = local.tags
  depends_on   = [time_sleep.kv_rbac_propagation]
}

# ---------------------------------------------------------------- AKS
module "aks" {
  source                  = "../../modules/aks"
  name                    = "aks-${local.name}"
  location                = var.location
  resource_group_name     = azurerm_resource_group.spoke.name
  tenant_id               = data.azurerm_client_config.current.tenant_id
  vnet_id                 = module.spoke.vnet_id
  node_subnet_id          = module.spoke.aks_nodes_subnet_id
  private_cluster_enabled = var.aks_private_cluster_enabled
  private_dns_zone_id     = module.hub.private_dns_zone_ids[local.private_dns_zones.aks]
  admin_group_object_ids  = var.aks_admin_group_object_ids
  outbound_type           = var.firewall_enabled ? "userDefinedRouting" : "loadBalancer"
  tags                    = local.tags

  # UDR must exist before the cluster when outbound_type = userDefinedRouting
  depends_on = [module.spoke, azurerm_private_dns_zone_virtual_network_link.spoke]
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = module.acr.id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_object_id
  principal_type       = "ServicePrincipal"
}

# ---------------------------------------------------------------- workload identities (least privilege)
module "wi_orders_api" {
  source                    = "../../modules/workload-identity"
  name                      = "${local.name}-orders-api"
  location                  = var.location
  resource_group_name       = azurerm_resource_group.spoke.name
  oidc_issuer_url           = module.aks.oidc_issuer_url
  service_account_namespace = var.app_namespace
  service_account_name      = "orders-api"
  tags                      = local.tags
  role_assignments = {
    # Read access to ONE secret, not the whole vault.
    db_password = { scope = azurerm_key_vault_secret.db_password.resource_versionless_id, role = "Key Vault Secrets User" }
  }
}

module "wi_worker" {
  source                    = "../../modules/workload-identity"
  name                      = "${local.name}-worker"
  location                  = var.location
  resource_group_name       = azurerm_resource_group.spoke.name
  oidc_issuer_url           = module.aks.oidc_issuer_url
  service_account_namespace = var.app_namespace
  service_account_name      = "worker"
  tags                      = local.tags
  role_assignments = {
    db_password = { scope = azurerm_key_vault_secret.db_password.resource_versionless_id, role = "Key Vault Secrets User" }
  }
}
