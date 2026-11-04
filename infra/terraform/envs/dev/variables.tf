variable "project" {
  type    = string
  default = "orders"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "location" {
  description = "Lowercase Azure region name (used in the AKS private DNS zone name)"
  type        = string
  default     = "centralindia"
}

variable "hub_address_space" {
  type    = string
  default = "10.0.0.0/16"
}

variable "spoke_address_space" {
  type    = string
  default = "10.10.0.0/16"
}

variable "aks_admin_group_object_ids" {
  description = "Entra ID group(s) granted cluster-admin on AKS"
  type        = list(string)
}

variable "aks_private_cluster_enabled" {
  type    = bool
  default = true
}

variable "firewall_enabled" {
  description = "Deploy Azure Firewall in the hub and force AKS egress through it (adds significant cost)"
  type        = bool
  default     = false
}

variable "management_ip_ranges" {
  description = <<-EOT
    Public IPs allowed to reach ACR / Key Vault data planes (bootstrap convenience only).
    Leave EMPTY in prod and run Terraform/CI from a self-hosted runner inside the hub VNet.
  EOT
  type        = list(string)
  default     = []
}

variable "app_namespace" {
  type    = string
  default = "orders"
}

variable "tags" {
  type    = map(string)
  default = {}
}
