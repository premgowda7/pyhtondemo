# Hub: shared connectivity + central Private DNS zones. Spokes peer to it.
resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet" # name is mandated by Azure
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.address_space, 10, 0)] # /26
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet" # reserved for VPN/ExpressRoute to on-prem
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.address_space, 11, 2)] # /27
}

resource "azurerm_subnet" "shared" {
  # Self-hosted GitHub runners / jumpbox: the only place that can reach private endpoints + private AKS API.
  name                 = "snet-shared-services"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.address_space, 8, 2)] # /24
}

# ---- Private DNS zones (centralised in the hub, linked to every spoke) ----
resource "azurerm_private_dns_zone" "this" {
  for_each            = toset(var.private_dns_zones)
  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  for_each             = azurerm_private_dns_zone.this
  name                 = "link-${azurerm_virtual_network.this.name}"
  private_dns_zone_id  = each.value.id
  virtual_network_id   = azurerm_virtual_network.this.id
  registration_enabled = false
  tags                 = var.tags
}

# ---- Optional Azure Firewall (egress control for AKS). ~USD 900+/month: off by default for dev. ----
resource "azurerm_public_ip" "firewall" {
  count               = var.firewall_enabled ? 1 : 0
  name                = "pip-afw-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones
  tags                = var.tags
}

resource "azurerm_firewall_policy" "this" {
  count                    = var.firewall_enabled ? 1 : 0
  name                     = "afwp-${var.name}"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  sku                      = "Standard"
  threat_intelligence_mode = "Deny"
  dns {
    proxy_enabled = true # required for FQDNs in network rules
  }
  tags = var.tags
}

resource "azurerm_firewall_policy_rule_collection_group" "aks" {
  count              = var.firewall_enabled ? 1 : 0
  name               = "aks-egress"
  firewall_policy_id = azurerm_firewall_policy.this[0].id
  priority           = 200

  application_rule_collection {
    name     = "aks-required"
    priority = 100
    action   = "Allow"
    rule {
      name                  = "aks-fqdn-tag"
      source_addresses      = var.egress_source_cidrs
      destination_fqdn_tags = ["AzureKubernetesService"] # MCR, AKS mgmt, Ubuntu updates, etc.
      protocols {
        type = "Https"
        port = 443
      }
    }
    rule {
      name              = "platform-dependencies"
      source_addresses  = var.egress_source_cidrs
      destination_fqdns = var.allowed_egress_fqdns # ArgoCD (GitHub), Helm repos, Dynatrace SaaS, Entra ID
      protocols {
        type = "Https"
        port = 443
      }
    }
  }

  network_rule_collection {
    name     = "aks-network"
    priority = 200
    action   = "Allow"
    rule {
      name                  = "ntp"
      source_addresses      = var.egress_source_cidrs
      destination_addresses = ["*"]
      destination_ports     = ["123"]
      protocols             = ["UDP"]
    }
  }
}

resource "azurerm_firewall" "this" {
  count               = var.firewall_enabled ? 1 : 0
  name                = "afw-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "AZFW_VNet"
  sku_tier            = "Standard"
  firewall_policy_id  = azurerm_firewall_policy.this[0].id
  zones               = var.zones

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall[0].id
  }
  tags = var.tags
}

resource "azurerm_network_security_group" "shared" {
  name                = "nsg-${var.name}-shared"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
  # No inbound rules: runners/jumpbox are reached via Azure Bastion or are outbound-only (GitHub runners poll).
}

resource "azurerm_subnet_network_security_group_association" "shared" {
  subnet_id                 = azurerm_subnet.shared.id
  network_security_group_id = azurerm_network_security_group.shared.id
}
