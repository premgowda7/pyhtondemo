output "vnet_id" { value = azurerm_virtual_network.this.id }
output "vnet_name" { value = azurerm_virtual_network.this.name }
output "aks_nodes_subnet_id" { value = azurerm_subnet.aks_nodes.id }
output "ingress_subnet_name" { value = azurerm_subnet.ingress.name }
output "private_endpoints_subnet_id" { value = azurerm_subnet.private_endpoints.id }
output "egress_route_table_association_id" {
  # Exposed so AKS can depend on the UDR existing before the cluster is created.
  value = try(azurerm_subnet_route_table_association.aks_nodes[0].id, null)
}
