variable "name" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "tenant_id" { type = string }
variable "tags" { type = map(string) }
variable "vnet_id" { type = string }
variable "node_subnet_id" { type = string }

variable "kubernetes_version" {
  description = "null = latest default; afterwards the patch channel keeps it current"
  type        = string
  default     = null
}

variable "sku_tier" {
  type    = string
  default = "Standard"
}

variable "private_cluster_enabled" {
  type    = bool
  default = true
}

variable "private_dns_zone_id" {
  description = "Hub-hosted privatelink.<region>.azmk8s.io zone"
  type        = string
  default     = null
}

variable "admin_group_object_ids" {
  description = "Entra ID groups that get cluster-admin"
  type        = list(string)
}

variable "zones" {
  type    = list(string)
  default = ["1", "2", "3"]
}

variable "system_node_vm_size" {
  type    = string
  default = "Standard_D2s_v5"
}

variable "system_node_min_count" {
  type    = number
  default = 2
}

variable "system_node_max_count" {
  type    = number
  default = 3
}

variable "user_node_vm_size" {
  type    = string
  default = "Standard_D4s_v5"
}

variable "user_node_min_count" {
  type    = number
  default = 2
}

variable "user_node_max_count" {
  type    = number
  default = 5
}

variable "pod_cidr" {
  type    = string
  default = "192.168.0.0/16"
}

variable "service_cidr" {
  description = "Must not overlap any VNet or on-prem range"
  type        = string
  default     = "172.16.0.0/16"
}

variable "outbound_type" {
  description = "loadBalancer (dev) or userDefinedRouting (egress via hub firewall)"
  type        = string
  default     = "loadBalancer"

  validation {
    condition     = contains(["loadBalancer", "userDefinedRouting"], var.outbound_type)
    error_message = "outbound_type must be loadBalancer or userDefinedRouting."
  }
}

variable "maintenance_utc_offset" {
  type    = string
  default = "+05:30"
}

variable "host_encryption_enabled" {
  description = "Encrypt temp/OS disk caches at the VM host. Needs: az feature register --namespace Microsoft.Compute --name EncryptionAtHost"
  type        = bool
  default     = true
}
