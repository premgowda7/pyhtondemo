output "vnet_id" { value = azurerm_virtual_network.this.id }
output "vnet_name" { value = azurerm_virtual_network.this.name }
output "shared_subnet_id" { value = azurerm_subnet.shared.id }
output "private_dns_zone_ids" { value = { for k, z in azurerm_private_dns_zone.this : k => z.id } }
output "firewall_private_ip" {
  value = var.firewall_enabled ? azurerm_firewall.this[0].ip_configuration[0].private_ip_address : null
}
