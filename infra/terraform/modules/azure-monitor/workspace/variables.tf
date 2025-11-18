/// Variables for Azure Monitor workspace module

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "rg_name" {
  type        = string
  description = "Resource group name where the Azure Monitor workspace will be created"
}

variable "location" {
  type        = string
  description = "Azure region for resources"
}

variable "environment_code" {
  type        = string
  description = "Environment code"
}

variable "workload_name" {
  type        = string
  description = "Primary workload or solution name used for resource naming suffixes"
}

variable "identifier" {
  type        = string
  description = "Optional identifier appended to resource names for uniqueness"
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to all resources"
  default     = {}
}

variable "public_network_access_enabled" {
  type        = bool
  description = "Enable public network access to the Azure Monitor workspace"
  default     = true
}
