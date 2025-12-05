# ─────────────────────────────────────────────────────────────────────────────
# Observability Stack Variables
# ─────────────────────────────────────────────────────────────────────────────

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID (unused directly; kept for symmetry)"
  type        = string
}

variable "environment_code" {
  description = "Environment code (e.g., dev, stg, prod)"
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
  description = "Optional identifier appended to resource names"
  type        = string
  default     = ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Observability configuration
# ─────────────────────────────────────────────────────────────────────────────

variable "log_retention_days" {
  description = "Log Analytics retention in days"
  type        = number
  default     = 30
}

variable "app_insights_daily_cap_gb" {
  description = "Daily data cap in GB for Application Insights"
  type        = number
  default     = 10
}

variable "public_network_access_enabled" {
  description = "Allow public network access to observability resources"
  type        = bool
  default     = true
}

variable "enable_dashboard" {
  description = "Create a basic Azure Portal dashboard wired to the observability resources"
  type        = bool
  default     = false
}

variable "enable_gateway_log_ingestion" {
  description = "Provision APISIX gateway log ingestion (DCE/DCR/custom table) for observability and tests"
  type        = bool
  default     = true
}

# ─────────────────────────────────────────────────────────────────────────────
# Tags
# ─────────────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
