variable "name" { type = string }
variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "tags" { type = map(string) }
variable "oidc_issuer_url" { type = string }
variable "service_account_namespace" { type = string }
variable "service_account_name" { type = string }

variable "role_assignments" {
  description = "key => { scope, role }. Scope as narrowly as possible (e.g. a single Key Vault secret)."
  type        = map(object({ scope = string, role = string }))
  default     = {}
}
