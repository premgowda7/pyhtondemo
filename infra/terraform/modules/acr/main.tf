resource "azurerm_container_registry" "this" {
  name                          = var.name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = "Premium" # required for Private Endpoints
  admin_enabled                 = false     # Entra ID only (AcrPull for AKS, AcrPush for CI)
  public_network_access_enabled = length(var.allowed_ip_ranges) > 0
  network_rule_bypass_option    = "AzureServices"
  anonymous_pull_enabled        = false
  data_endpoint_enabled         = true
  retention_policy_in_days      = 7 # purge untagged manifests
  tags                          = var.tags

  network_rule_set {
    default_action = "Deny"
    ip_rule        = [for ip in var.allowed_ip_ranges : { action = "Allow", ip_range = ip }]
  }
}
