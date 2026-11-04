variable "name" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "subnet_id" { type = string }
variable "resource_id" { type = string }
variable "tags" { type = map(string) }

variable "subresource_name" {
  description = "registry | vault | postgresqlServer | ..."
  type        = string
}

variable "private_dns_zone_id" { type = string }
