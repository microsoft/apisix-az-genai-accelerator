/// Module: aca/environment
/// Purpose: Resource group, Log Analytics workspace, and Container Apps Environment

# ─────────────────────────────────────────────────────────────────────────────
# Core configuration
# ─────────────────────────────────────────────────────────────────────────────

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
# Log Analytics configuration
# ─────────────────────────────────────────────────────────────────────────────

variable "log_analytics_workspace_id" {
  description = "Existing Log Analytics workspace ID (optional; will create if not provided)"
  type        = string
  default     = ""
  validation {
    condition     = can(regex("^/subscriptions/.*/resourceGroups/.*/providers/Microsoft.OperationalInsights/workspaces/.*$", var.log_analytics_workspace_id)) || var.log_analytics_workspace_id == ""
    error_message = "log_analytics_workspace_id must be a valid Azure Log Analytics workspace resource ID or empty string"
  }
}

variable "log_retention_days" {
  description = "Log Analytics retention in days"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Networking
# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────
# Naming overrides
# ─────────────────────────────────────────────────────────────────────────────

variable "rg_name_override" {
  description = "Override auto-generated resource group name"
  type        = string
  default     = ""
}

variable "aca_env_name_override" {
  description = "Override auto-generated ACA environment name"
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
