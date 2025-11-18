variable "workload_name" {
  description = "The workload name prefix for all resources"
  type        = string
}

variable "environment" {
  description = "The environment name"
  type        = string
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "key_vault_name_override" {
  description = "Override name for the Key Vault (must be globally unique)"
  type        = string
  default     = ""
}

variable "identity_name_override" {
  description = "Override name for the user-assigned managed identity. Leave empty to use standard naming."
  type        = string
  default     = ""
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the private endpoint (if null, no private endpoint is created)"
  type        = string
  default     = null
}

variable "purge_protection_enabled" {
  description = "Whether to enable Key Vault purge protection"
  type        = bool
  default     = true
}

variable "private_dns_zone_id" {
  description = "Private DNS zone ID for Key Vault"
  type        = string
  default     = null
}

variable "deployment_principal_id" {
  description = "Principal ID of the deployment service principal for initial access"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
variable "identifier" {
  description = "Optional identifier appended to resource names for uniqueness"
  type        = string
  default     = ""
}

variable "ip_rules" {
  description = "Optional list of public IPs or CIDRs to allow when no private endpoint is used"
  type        = list(string)
  default     = []
}
