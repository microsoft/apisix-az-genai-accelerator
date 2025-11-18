# ─────────────────────────────────────────────────────────────────────────────
# Workload Stack Variables
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
# Foundation outputs
# ─────────────────────────────────────────────────────────────────────────────

variable "platform_resource_group_name" {
  description = "Platform resource group name from foundation stack"
  type        = string
}

variable "platform_acr_name" {
  description = "Platform Azure Container Registry name from foundation stack"
  type        = string
}

variable "key_vault_name" {
  description = "Key Vault name from foundation stack for secrets management"
  type        = string
  validation {
    condition     = length(trimspace(var.key_vault_name)) > 0
    error_message = "key_vault_name is required"
  }
}

variable "aca_managed_identity_id" {
  description = "Managed identity ID with Key Vault access from foundation stack"
  type        = string
  validation {
    condition     = can(regex("^/subscriptions/.*/resourceGroups/.*/providers/Microsoft.ManagedIdentity/userAssignedIdentities/.*$", var.aca_managed_identity_id))
    error_message = "aca_managed_identity_id must be a valid user-assigned managed identity resource ID"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Remote state configuration
# ─────────────────────────────────────────────────────────────────────────────

variable "state_resource_group_name" {
  description = "Resource group containing Terraform state storage"
  type        = string
}

variable "state_storage_account_name" {
  description = "Storage account name hosting Terraform state"
  type        = string
}

variable "state_container_name" {
  description = "Blob container name for Terraform state"
  type        = string
}

variable "foundation_state_blob_key" {
  description = "Blob key for the foundation stack Terraform state file"
  type        = string
}

variable "openai_state_blob_key" {
  description = "Blob key for the OpenAI stack Terraform state file"
  type        = string
}

# ─────────────────────────────────────────────────────────────────────────────
# Application configuration
# ─────────────────────────────────────────────────────────────────────────────

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

variable "gateway_image" {
  description = "Gateway container image"
  type        = string
  validation {
    condition     = length(trimspace(var.gateway_image)) > 0
    error_message = "gateway_image is required"
  }
}

variable "hydrenv_image" {
  description = "Hydrenv config renderer image"
  type        = string
  validation {
    condition     = length(trimspace(var.hydrenv_image)) > 0
    error_message = "hydrenv_image is required"
  }
}

variable "use_provisioned_azure_openai" {
  description = "Use Azure OpenAI endpoints provisioned by foundation stack (auto-detected by setup script)"
  type        = bool
  default     = false
}

variable "direct_environment_variables" {
  description = "Environment variables injected directly into the Container Apps workload"
  type        = map(string)
  default     = {}
}

variable "gateway_e2e_test_mode" {
  description = "Enable E2E test mode (deploy config API sidecar and simulators)"
  type        = bool
  default     = false
}

variable "config_api_image" {
  description = "Gateway config API sidecar image"
  type        = string
  default     = ""
}

variable "config_api_shared_secret" {
  description = "Shared secret for config API"
  type        = string
  default     = ""
}

variable "simulator_image" {
  description = "AOAI API simulator image for test mode"
  type        = string
  default     = ""
}

variable "simulator_api_key" {
  description = "API key expected by simulators and used by the gateway in test mode"
  type        = string
  default     = ""
}

variable "simulator_port" {
  description = "Port the simulator listens on"
  type        = number
  default     = 8000
}

variable "simulator_client_ips" {
  description = "Additional client CIDRs allowed to reach simulators when public ingress is enabled"
  type        = list(string)
  default     = []
}

variable "secret_keys" {
  description = "List of environment variable names treated as secrets"
  type        = list(string)
  default     = []
}

# ─────────────────────────────────────────────────────────────────────────────
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
}

variable "gateway_max_replicas" {
  description = "Maximum number of gateway replicas"
  type        = number
  default     = 3
}

# ─────────────────────────────────────────────────────────────────────────────
# Observability
# ─────────────────────────────────────────────────────────────────────────────

variable "log_analytics_workspace_id" {
  description = "Existing Log Analytics workspace ID (optional, otherwise created)"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "Log Analytics retention in days"
  type        = number
  default     = 30
}

variable "app_insights_connection_string" {
  description = "Existing Application Insights connection string"
  type        = string
  default     = ""
  sensitive   = true
}

variable "app_insights_daily_cap_gb" {
  description = "Daily data cap in GB for Application Insights"
  type        = number
  default     = 10
}

variable "otel_collector_image" {
  description = "OTel Collector container image"
  type        = string
  default     = "otel/opentelemetry-collector-contrib:0.138.0"
}

# ─────────────────────────────────────────────────────────────────────────────
# Alerts
# ─────────────────────────────────────────────────────────────────────────────

variable "enable_alerts" {
  description = "Enable Azure Monitor alert rules"
  type        = bool
  default     = false
}

variable "alert_email_receivers" {
  description = "List of email receivers for alerts"
  type = list(object({
    name  = string
    email = string
  }))
  default = []
}

variable "alert_webhook_receivers" {
  description = "List of webhook receivers for alerts"
  type = list(object({
    name = string
    uri  = string
  }))
  default = []
}

variable "alert_5xx_threshold_percent" {
  description = "Alert threshold for 5xx error rate (percentage)"
  type        = number
  default     = 5.0
}

variable "alert_429_threshold_percent" {
  description = "Alert threshold for 429 throttling rate (percentage)"
  type        = number
  default     = 10.0
}

variable "alert_latency_p95_threshold_ms" {
  description = "Alert threshold for P95 latency (milliseconds)"
  type        = number
  default     = 5000
}

# ─────────────────────────────────────────────────────────────────────────────
# Naming overrides
# ─────────────────────────────────────────────────────────────────────────────

variable "workload_rg_name_override" {
  description = "Override auto-generated workload resource group name"
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
