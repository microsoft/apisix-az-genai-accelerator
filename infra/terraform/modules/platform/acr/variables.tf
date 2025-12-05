/// Module: platform/acr
/// Purpose: Azure Container Registry with optional private endpoint

# ─────────────────────────────────────────────────────────────────────────────
# Core inputs
# ─────────────────────────────────────────────────────────────────────────────
variable "resource_group_name" {
  description = "Resource group in which to create the Azure Container Registry"
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

variable "acr_name_override" {
  description = "Override the auto-generated name for the ACR"
  type        = string
  default     = ""
}

# ─────────────────────────────────────────────────────────────────────────────
# ACR configuration
# ─────────────────────────────────────────────────────────────────────────────

variable "acr_sku" {
  description = "SKU for Azure Container Registry"
  type        = string
  default     = "Premium"
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], title(var.acr_sku))
    error_message = "acr_sku must be Basic, Standard, or Premium"
  }
}

variable "acr_admin_enabled" {
  description = "Enable admin user on Azure Container Registry"
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "Allow public network access to the registry"
  type        = bool
  default     = true
}

# ─────────────────────────────────────────────────────────────────────────────
# Observability
# ─────────────────────────────────────────────────────────────────────────────

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostics"
  type        = string
  validation {
    condition = (
      var.log_analytics_workspace_id == ""
      || can(regex("^/subscriptions/.*/resourceGroups/.*/providers/Microsoft.OperationalInsights/workspaces/.*$", var.log_analytics_workspace_id))
    )
    error_message = "log_analytics_workspace_id must be empty or a valid Azure Log Analytics workspace resource ID"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Tags
# ─────────────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
