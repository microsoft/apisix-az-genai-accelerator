variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "environment_code" {
  description = "Environment code (dev, stg, prod)"
  type        = string
}

variable "location" {
  description = "Primary Azure region for OpenAI resources"
  type        = string
}

variable "workload_name" {
  description = "Workload or project name used for naming conventions"
  type        = string
  default     = "apisix"
}

variable "identifier" {
  description = "Optional identifier appended to resource names"
  type        = string
  default     = ""
}


variable "azure_openai_instances" {
  description = "Azure OpenAI instances to deploy (supports 0-N instances)"
  type = list(object({
    name_suffix                   = string
    location                      = optional(string)
    sku_name                      = optional(string, "S0")
    priority                      = optional(number, 5)
    weight                        = optional(number, 1)
    public_network_access_enabled = optional(bool)
    deployments = list(object({
      name = string
      model = object({
        name    = string
        version = string
      })
      scale_type                 = optional(string, "Standard")
      capacity                   = optional(number, 1)
      dynamic_throttling_enabled = optional(bool, false)
      version_upgrade_option     = optional(string, "OnceNewDefaultVersionAvailable")
    }))
  }))
  default = []

  validation {
    condition     = length(var.azure_openai_instances) <= 10
    error_message = "Maximum 10 Azure OpenAI instances supported"
  }
}

variable "azure_openai_network_isolation" {
  description = "Enable private endpoints and DNS for Azure OpenAI (disables public network access)"
  type        = bool
  default     = true
}

variable "azure_openai_custom_subdomain_prefix" {
  description = "Custom prefix for OpenAI subdomain (leave empty for auto-generated)"
  type        = string
  default     = ""
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostic settings (optional)"
  type        = string
  default     = ""
}

variable "remote_state_resource_group_name" {
  description = "Resource group containing Terraform remote state storage"
  type        = string
}

variable "remote_state_storage_account_name" {
  description = "Storage account hosting Terraform remote state"
  type        = string
}

variable "remote_state_container_name" {
  description = "Blob container for Terraform remote state"
  type        = string
}

variable "foundation_state_blob_key" {
  description = "Blob key for the foundation stack Terraform state file"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
