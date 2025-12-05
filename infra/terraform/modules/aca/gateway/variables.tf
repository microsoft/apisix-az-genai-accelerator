/// Module: aca/gateway
/// Purpose: Container App (init + main + optional sidecars), UA identity, env/secret parsing, registry auth

# ─────────────────────────────────────────────────────────────────────────────
# Core configuration
# ─────────────────────────────────────────────────────────────────────────────

variable "rg_name" {
  description = "Resource group name"
  type        = string
}

variable "aca_env_id" {
  description = "Container Apps environment ID"
  type        = string
  validation {
    condition     = can(regex("^/subscriptions/.*/resourceGroups/.*/providers/Microsoft.App/managedEnvironments/.*$", var.aca_env_id))
    error_message = "aca_env_id must be a valid Container Apps environment resource ID"
  }
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
  description = "Azure region"
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

# ─────────────────────────────────────────────────────────────────────────────
# Key Vault configuration
# ─────────────────────────────────────────────────────────────────────────────

variable "key_vault_name" {
  description = "Name of the Azure Key Vault containing secrets"
  type        = string
}

variable "key_vault_managed_identity_id" {
  description = "ID of the managed identity for Key Vault access"
  type        = string
  validation {
    condition     = can(regex("^/subscriptions/.*/resourceGroups/.*/providers/Microsoft.ManagedIdentity/userAssignedIdentities/.*$", var.key_vault_managed_identity_id))
    error_message = "key_vault_managed_identity_id must be a valid user-assigned managed identity resource ID"
  }
}

variable "app_settings" {
  description = "Application settings (non-secret configuration)"
  type        = map(string)
  default     = {}
}

variable "secret_names" {
  description = "List of secret names in Key Vault"
  type        = list(string)
  default     = []
}

variable "direct_environment_variables" {
  description = "Additional environment variables injected directly into the containers"
  type        = map(string)
  default     = {}
}

# ─────────────────────────────────────────────────────────────────────────────
# ACR configuration (external/platform ACR is required)
# ─────────────────────────────────────────────────────────────────────────────

variable "platform_acr_id" {
  description = "ID of the platform ACR (created by bootstrap or provided externally)"
  type        = string
  validation {
    condition     = var.platform_acr_id != ""
    error_message = "platform_acr_id is required"
  }
}

variable "platform_acr_login" {
  description = "Login server of the platform ACR"
  type        = string
  validation {
    condition     = var.platform_acr_login != ""
    error_message = "platform_acr_login is required"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Container images
# ─────────────────────────────────────────────────────────────────────────────

variable "gateway_image" {
  description = "Gateway container image"
  type        = string
  validation {
    condition     = length(trimspace(var.gateway_image)) > 0
    error_message = "gateway_image is required and must not be empty"
  }
}

variable "hydrenv_image" {
  description = "Hydrenv config renderer image (init container)"
  type        = string
  validation {
    condition     = length(trimspace(var.hydrenv_image)) > 0
    error_message = "hydrenv_image is required and must not be empty"
  }
}

variable "gateway_e2e_test_mode" {
  description = "Enable E2E test mode (adds config API sidecar and extra routes)"
  type        = bool
  default     = false
}

variable "config_api_image" {
  description = "Config API sidecar image for E2E test mode"
  type        = string
  default     = ""
}

variable "config_api_shared_secret" {
  description = "Shared secret for config API (optional)"
  type        = string
  default     = ""
}

variable "config_api_cpu" {
  description = "CPU cores for config API sidecar"
  type        = number
  default     = 0.25
}

variable "config_api_memory" {
  description = "Memory for config API sidecar"
  type        = string
  default     = "0.5Gi"
}


# Gateway configuration
# ─────────────────────────────────────────────────────────────────────────────

variable "expose_gateway_public" {
  description = "Expose gateway with public ingress"
  type        = bool
  default     = true
}

variable "gateway_target_port" {
  description = "Gateway container listening port"
  type        = number
  default     = 9080
  validation {
    condition     = var.gateway_target_port > 0 && var.gateway_target_port <= 65535
    error_message = "gateway_target_port must be between 1 and 65535"
  }
}

variable "gateway_cpu" {
  description = "CPU cores for gateway container"
  type        = number
  default     = 0.5
}

variable "gateway_memory" {
  description = "Memory for gateway container"
  type        = string
  default     = "1Gi"
}

variable "gateway_min_replicas" {
  description = "Minimum number of gateway replicas"
  type        = number
  default     = 1
  validation {
    condition     = var.gateway_min_replicas >= 0
    error_message = "gateway_min_replicas must be >= 0"
  }
}

variable "gateway_max_replicas" {
  description = "Maximum number of gateway replicas"
  type        = number
  default     = 3
  validation {
    condition     = var.gateway_max_replicas >= var.gateway_min_replicas
    error_message = "gateway_max_replicas must be >= gateway_min_replicas"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Observability
# ─────────────────────────────────────────────────────────────────────────────

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID"
  type        = string
  validation {
    condition     = can(regex("^/subscriptions/.*/resourceGroups/.*/providers/Microsoft.OperationalInsights/workspaces/.*$", var.log_analytics_workspace_id))
    error_message = "log_analytics_workspace_id must be a valid Log Analytics workspace resource ID"
  }
}

variable "app_insights_daily_cap_gb" {
  description = "Daily data cap in GB for Application Insights"
  type        = number
  default     = 10
}

variable "app_insights_connection_string" {
  description = "Existing Application Insights connection string (skips creation when provided)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "azure_monitor_workspace_id" {
  description = "Azure Monitor workspace ID for Prometheus metrics"
  type        = string
  validation {
    condition     = can(regex("^/subscriptions/.*/resourceGroups/.*/providers/Microsoft.Monitor/accounts/.*$", var.azure_monitor_workspace_id))
    error_message = "azure_monitor_workspace_id must be a valid Azure Monitor workspace resource ID"
  }
}

variable "azure_monitor_prometheus_endpoint" {
  description = "Azure Monitor Prometheus remote-write base endpoint (without /api/v1/write)"
  type        = string
  validation {
    condition     = can(regex("^https://.+", var.azure_monitor_prometheus_endpoint))
    error_message = "azure_monitor_prometheus_endpoint must be a valid https URL"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Observability sidecars
# ─────────────────────────────────────────────────────────────────────────────

variable "otel_collector_image" {
  description = "OTel Collector container image"
  type        = string
  default     = "otel/opentelemetry-collector-contrib:0.138.0"
}

variable "otel_collector_cpu" {
  description = "CPU cores for OTel Collector sidecar"
  type        = number
  default     = 0.25
}

variable "otel_collector_memory" {
  description = "Memory for OTel Collector sidecar"
  type        = string
  default     = "0.5Gi"
}

# ─────────────────────────────────────────────────────────────────────────────
# Tags
# ─────────────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
