resource "azurerm_private_endpoint" "this" {
  name                          = "pe-${var.name}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  subnet_id                     = var.subnet_id
  custom_network_interface_name = "nic-pe-${var.name}"
  tags                          = var.tags

  private_service_connection {
    name                           = "psc-${var.name}"
    private_connection_resource_id = var.resource_id
    subresource_names              = [var.subresource_name]
    is_manual_connection           = false
  }

  # Registers the A record in the hub's Private DNS zone automatically.
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_id]
  }
}
