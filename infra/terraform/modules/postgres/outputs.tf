output "id" { value = azurerm_postgresql_flexible_server.this.id }
output "fqdn" { value = azurerm_postgresql_flexible_server.this.fqdn }
output "administrator_login" { value = azurerm_postgresql_flexible_server.this.administrator_login }
output "database_name" { value = azurerm_postgresql_flexible_server_database.this.name }

output "administrator_password" {
  value     = random_password.admin.result
  sensitive = true
}
