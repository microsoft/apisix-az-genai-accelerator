# ─────────────────────────────────────────────────────────────────────────────
# Foundation Stack Variables
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
  description = "Optional identifier appended to resource names"
  type        = string
  default     = ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Naming overrides
# ─────────────────────────────────────────────────────────────────────────────

variable "platform_rg_name_override" {
  description = "Override name for the platform resource group"
  type        = string
  default     = ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Container registry configuration
# ─────────────────────────────────────────────────────────────────────────────

variable "acr_name_override" {
  description = "Override name for the Azure Container Registry"
  type        = string
  default     = ""
}

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

# ─────────────────────────────────────────────────────────────────────────────
# Observability
# ─────────────────────────────────────────────────────────────────────────────

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostics"
  type        = string
  default     = ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Key Vault configuration
# ─────────────────────────────────────────────────────────────────────────────

variable "key_vault_name_override" {
  description = "Override name for the Key Vault (must be globally unique)"
  type        = string
  default     = ""
}

variable "key_vault_identity_name_override" {
  description = "Override name for the Key Vault managed identity"
  type        = string
  default     = ""
}

variable "key_vault_purge_protection_enabled" {
  description = "Enable purge protection for the platform Key Vault"
  type        = bool
  default     = true
}

variable "enable_key_vault_public_ip_allowlist" {
  description = "Allow current public IP to access the Key Vault (intended for e2e/test only)"
  type        = bool
  default     = false
}

variable "deployment_principal_id" {
  description = "Principal ID of deployment service principal for Key Vault RBAC (optional)"
  type        = string
  default     = null
}

# ─────────────────────────────────────────────────────────────────────────────
# Tags
# ─────────────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
