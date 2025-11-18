variable "name" {
  description = "Name of the Azure AI Foundry account"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name for the account"
  type        = string
}

variable "location" {
  description = "Azure region for the account"
  type        = string
}

variable "sku_name" {
  description = "SKU name for the Foundry account"
  type        = string
  default     = "S0"
}

variable "custom_subdomain_name" {
  description = "Optional custom subdomain name"
  type        = string
  default     = null
}

variable "public_network_access_enabled" {
  description = "Whether public network access is enabled"
  type        = bool
  default     = true
}

variable "allow_project_management" {
  description = "Enable project management child resources"
  type        = bool
  default     = true
}

variable "deployments" {
  description = "Model deployments to provision"
  type = list(object({
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
  default = []
}

variable "environment_code" {
  description = "Environment code (e.g. dev, stg, prod)"
  type        = string
}

variable "workload_name" {
  description = "Workload name used for naming conventions"
  type        = string
}

variable "identifier" {
  description = "Optional identifier suffix for generated resource names"
  type        = string
  default     = ""
}

variable "instance_suffix" {
  description = "Instance suffix used for tagging and naming artifacts"
  type        = string
}

variable "instance_index" {
  description = "Zero-based index of this instance for unique naming"
  type        = number
}

variable "enable_private_endpoint" {
  description = "Enable private endpoint integration"
  type        = bool
  default     = false
}

variable "private_dns_zone_id" {
  description = "Private DNS zone ID to associate with the private endpoint"
  type        = string
  default     = ""
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID where the private endpoint should reside"
  type        = string
  default     = ""
}

variable "private_endpoint_location" {
  description = "Location to use for the private endpoint (defaults to account location if not set)"
  type        = string
  default     = null
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID for diagnostics"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Base tags to apply to resources"
  type        = map(string)
  default     = {}
}
