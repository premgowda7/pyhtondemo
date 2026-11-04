variable "name" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "tags" { type = map(string) }

variable "allowed_ip_ranges" {
  description = "Public IPs allowed through the ACR firewall. Empty = private endpoint only (recommended)."
  type        = list(string)
  default     = []
}
