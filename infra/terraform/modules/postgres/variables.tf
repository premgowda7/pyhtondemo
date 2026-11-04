variable "name" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "tenant_id" { type = string }
variable "tags" { type = map(string) }

variable "administrator_login" {
  type    = string
  default = "pgadmin"
}

variable "database_name" {
  type    = string
  default = "orders"
}

variable "sku_name" {
  description = "B_Standard_B1ms for dev; GP_Standard_D2ds_v5+ for prod"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "storage_mb" {
  type    = number
  default = 32768
}

variable "storage_tier" {
  type    = string
  default = "P4"
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "geo_redundant_backup_enabled" {
  type    = bool
  default = false
}

variable "high_availability" {
  description = "Zone-redundant HA (not supported on Burstable SKUs)"
  type        = bool
  default     = false
}
