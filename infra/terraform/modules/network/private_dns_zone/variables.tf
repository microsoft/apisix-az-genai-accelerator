variable "name" {
  description = "(Required) Specifies the name of the private dns zone"
  type        = string
}

variable "resource_group_name" {
  description = "(Required) Specifies the resource group name of the private dns zone"
  type        = string
}

variable "tags" {
  description = "(Optional) Specifies the tags of the private dns zone"
  default     = {}
}

variable "virtual_networks_to_link_id" {
  description = "(Optional) Specifies the virtual networks id to which create a virtual network link"
  type        = string
}

variable "environment_code" {
  description = "Environment code"
  type        = string
}

variable "region_code" {
  description = "Azure region short code (e.g., eus)"
  type        = string
  default     = ""
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

variable "link_name_override" {
  description = "Override auto-generated virtual network link name"
  type        = string
  default     = ""
}
