/// Variables for APIM-style gateway log ingestion (DCR + DCE)

variable "workspace_id" {
  type        = string
  description = "Target Log Analytics workspace resource ID"
}

variable "location" {
  type        = string
  description = "Azure region for DCE/DCR"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group for DCE/DCR"
}

variable "stream_name" {
  type        = string
  description = "Destination stream name (default: Custom-APISIXGatewayLogs)"
  default     = "Custom-APISIXGatewayLogs"
}

variable "custom_table_name" {
  type        = string
  description = "Custom Log Analytics table name (only used when stream_name starts with Custom-). Should end with _CL."
  default     = ""
}

variable "dce_name" {
  type        = string
  description = "Data Collection Endpoint name"
  default     = ""
}

variable "dcr_name" {
  type        = string
  description = "Data Collection Rule name"
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to DCE/DCR"
  default     = {}
}
