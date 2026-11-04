variable "name" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "address_space" { type = string }
variable "tags" { type = map(string) }

variable "zones" {
  type    = list(string)
  default = ["1", "2", "3"]
}

variable "private_dns_zones" {
  description = "Private Link DNS zones hosted centrally in the hub"
  type        = list(string)
}

variable "firewall_enabled" {
  type    = bool
  default = false
}

variable "egress_source_cidrs" {
  description = "Spoke CIDRs allowed to egress through the firewall"
  type        = list(string)
  default     = []
}

variable "allowed_egress_fqdns" {
  type    = list(string)
  default = []
}
