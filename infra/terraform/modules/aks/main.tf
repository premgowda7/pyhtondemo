# Control-plane identity is created up front so it can be granted rights on the
# BYO VNet and the hub's private DNS zone *before* the cluster is created.
resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "id-${var.name}-control-plane"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "network_contributor" {
  scope                = var.vnet_id # node subnet + ingress subnet (internal LB) + route table
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "private_dns" {
  count                = var.private_cluster_enabled ? 1 : 0
  scope                = var.private_dns_zone_id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  node_resource_group = "${var.resource_group_name}-nodes"
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier # Standard = financially-backed API server SLA
  tags                = var.tags

  # Private API server: only reachable from the hub/spoke (self-hosted runners, jumpbox, VPN).
  private_cluster_enabled    = var.private_cluster_enabled
  private_dns_zone_id        = var.private_cluster_enabled ? var.private_dns_zone_id : null
  dns_prefix                 = var.private_cluster_enabled ? null : var.name
  dns_prefix_private_cluster = var.private_cluster_enabled ? var.name : null

  # Identity & access
  oidc_issuer_enabled               = true # required for workload identity
  workload_identity_enabled         = true
  local_account_disabled            = true # no static kubeconfig admin cert - Entra ID only
  azure_policy_enabled              = true
  role_based_access_control_enabled = true

  azure_active_directory_role_based_access_control {
    tenant_id              = var.tenant_id
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
  }

  # Upgrades & hygiene
  automatic_upgrade_channel    = "patch"
  node_os_upgrade_channel      = "NodeImage"
  image_cleaner_enabled        = true
  image_cleaner_interval_hours = 48

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "02:00"
    utc_offset  = var.maintenance_utc_offset
  }

  maintenance_window_node_os {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Saturday"
    start_time  = "02:00"
    utc_offset  = var.maintenance_utc_offset
  }

  # System pool runs only critical add-ons (CoreDNS, CSI, konnectivity...).
  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_node_vm_size
    auto_scaling_enabled         = true
    min_count                    = var.system_node_min_count
    max_count                    = var.system_node_max_count
    vnet_subnet_id               = var.node_subnet_id
    zones                        = var.zones
    only_critical_addons_enabled = true
    host_encryption_enabled      = var.host_encryption_enabled
    os_sku                       = "AzureLinux"
    temporary_name_for_rotation  = "systemtmp"

    upgrade_settings {
      max_surge = "33%"
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay" # pods get IPs from pod_cidr, saves VNet address space
    network_data_plane  = "cilium"
    network_policy      = "cilium" # enforces the chart's NetworkPolicies
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = cidrhost(var.service_cidr, 10)
    outbound_type       = var.outbound_type
    load_balancer_sku   = "standard"
  }

  # Classic node pools + cluster autoscaler. ("Auto" = Node Auto-Provisioning / Karpenter.)
  node_provisioning_profile {
    mode = "Manual"
  }

  # Key Vault Secrets Store CSI driver add-on, with rotation polling.
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count, # owned by the cluster autoscaler
      kubernetes_version,              # owned by the auto-upgrade channel
    ]
  }

  depends_on = [
    azurerm_role_assignment.network_contributor,
    azurerm_role_assignment.private_dns,
  ]
}

# Application workloads land here, away from system pods.
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                    = "user"
  kubernetes_cluster_id   = azurerm_kubernetes_cluster.this.id
  mode                    = "User"
  vm_size                 = var.user_node_vm_size
  auto_scaling_enabled    = true
  host_encryption_enabled = var.host_encryption_enabled
  min_count               = var.user_node_min_count
  max_count               = var.user_node_max_count
  vnet_subnet_id          = var.node_subnet_id
  zones                   = var.zones
  os_sku                  = "AzureLinux"
  tags                    = var.tags

  upgrade_settings {
    max_surge = "33%"
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}
