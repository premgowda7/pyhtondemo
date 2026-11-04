output "id" { value = azurerm_kubernetes_cluster.this.id }
output "name" { value = azurerm_kubernetes_cluster.this.name }
output "oidc_issuer_url" { value = azurerm_kubernetes_cluster.this.oidc_issuer_url }
output "kubelet_object_id" { value = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id }
output "control_plane_principal_id" { value = azurerm_user_assigned_identity.control_plane.principal_id }
output "node_resource_group" { value = azurerm_kubernetes_cluster.this.node_resource_group }
