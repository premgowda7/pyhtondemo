variable "name" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "address_space" { type = string }
variable "tags" { type = map(string) }

variable "firewall_private_ip" {
  description = "Hub firewall IP. When set, a 0.0.0.0/0 UDR is attached to the AKS node subnet."
  type        = string
  default     = null
}

variable "ingress_allowed_cidrs" {
  description = "Who may reach Kong's internal load balancer (hub / App Gateway / on-prem ranges)"
  type        = list(string)
}
