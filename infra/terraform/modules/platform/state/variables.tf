/// Module: platform/state
/// Purpose: Remote state storage account, resource group, and RBAC

# ─────────────────────────────────────────────────────────────────────────────
# Core identity & location
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

variable "workload_name" {
  description = "Primary workload or solution name used for resource naming suffixes"
  type        = string
}

variable "identifier" {
  description = "Optional identifier appended to resource names for uniqueness"
  type        = string
  default     = ""
}

variable "location" {
  description = "Azure region (e.g., eastus, westeurope)"
  type        = string
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
  validation {
    condition     = var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365
    error_message = "soft_delete_retention_days must be between 1 and 365"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Network & access control
# ─────────────────────────────────────────────────────────────────────────────

variable "allowed_public_ip_addresses" {
  description = "List of public IPv4 addresses permitted to access the state storage account (exact IP matches)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for ip in var.allowed_public_ip_addresses : can(cidrhost("${ip}/32", 0))])
    error_message = "Each allowed public IP address must be a valid IPv4 address."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Observability
# ─────────────────────────────────────────────────────────────────────────────


# ─────────────────────────────────────────────────────────────────────────────
# Naming overrides
# ─────────────────────────────────────────────────────────────────────────────

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
