# ─────────────────────────────────────────────────────────────────────────────
# Bootstrap Stack Variables
# ─────────────────────────────────────────────────────────────────────────────

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "environment_code" {
  description = "Environment code"
  type        = string
}

variable "location" {
  description = "Azure region (e.g., eastus, westeurope)"
  type        = string
}

variable "workload_name" {
  description = "Primary workload or solution name used for resource naming suffixes"
  type        = string
  default     = "apisix"
}

variable "identifier" {
  description = "Optional identifier appended to resource names for uniqueness"
  type        = string
  default     = ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Storage account configuration
# ─────────────────────────────────────────────────────────────────────────────

variable "sa_replication_type" {
  description = "Storage account replication type"
  type        = string
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], upper(var.sa_replication_type))
    error_message = "sa_replication_type must be LRS, GRS, RAGRS, GZRS, or RAGZRS"
  }
}

variable "soft_delete_retention_days" {
  description = "Days a soft-deleted blob remains recoverable"
  type        = number
  default     = 30
}

variable "private_link_subnet_id" {
  description = "Subnet ID for private endpoints (optional)"
  type        = string
  default     = ""
}

variable "enable_state_sa_private_endpoint" {
  description = "Create private endpoint for state storage account"
  type        = bool
  default     = false
}

variable "state_rg_name_override" {
  description = "Override auto-generated state resource group name"
  type        = string
  default     = ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Tags
# ─────────────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
