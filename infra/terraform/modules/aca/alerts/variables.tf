/// Module: aca/alerts
/// Purpose: Azure Monitor alert rules and action groups for gateway monitoring

# ─────────────────────────────────────────────────────────────────────────────
# Variables
# ─────────────────────────────────────────────────────────────────────────────

variable "enable_alerts" {
  description = "Enable Azure Monitor alert rules"
  type        = bool
  default     = false
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

variable "law_id" {
  description = "Log Analytics workspace ID for alert queries"
  type        = string
  validation {
    condition     = can(regex("^/subscriptions/.*/resourceGroups/.*/providers/Microsoft.OperationalInsights/workspaces/.*$", var.law_id))
    error_message = "law_id must be a valid Azure Log Analytics workspace resource ID"
  }
}

variable "gateway_app_name" {
  description = "Name of the gateway Container App for alert queries"
  type        = string
}

variable "rg_name" {
  description = "Resource group name for alerts"
  type        = string
}

variable "location" {
  description = "Azure region for alerts"
  type        = string
}

# ─────────────────────────────────────────────────────────────────────────────
# Alert receivers
# ─────────────────────────────────────────────────────────────────────────────

variable "alert_email_receivers" {
  description = "List of email receivers for alerts"
  type = list(object({
    name  = string
    email = string
  }))
  default = []
  validation {
    condition = alltrue([
      for receiver in var.alert_email_receivers : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", receiver.email))
    ])
    error_message = "All email addresses must be valid"
  }
}

variable "alert_webhook_receivers" {
  description = "List of webhook receivers for alerts (Slack, Teams, PagerDuty, etc.)"
  type = list(object({
    name = string
    uri  = string
  }))
  default = []
  validation {
    condition = alltrue([
      for receiver in var.alert_webhook_receivers : can(regex("^https://.*", receiver.uri))
    ])
    error_message = "All webhook URIs must be HTTPS URLs"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Alert thresholds
# ─────────────────────────────────────────────────────────────────────────────

variable "alert_5xx_threshold_percent" {
  description = "Alert threshold for 5xx error rate (percentage)"
  type        = number
  default     = 5.0
  validation {
    condition     = var.alert_5xx_threshold_percent >= 0 && var.alert_5xx_threshold_percent <= 100
    error_message = "alert_5xx_threshold_percent must be between 0 and 100"
  }
}

variable "alert_429_threshold_percent" {
  description = "Alert threshold for 429 throttling rate (percentage)"
  type        = number
  default     = 10.0
  validation {
    condition     = var.alert_429_threshold_percent >= 0 && var.alert_429_threshold_percent <= 100
    error_message = "alert_429_threshold_percent must be between 0 and 100"
  }
}

variable "alert_latency_p95_threshold_ms" {
  description = "Alert threshold for P95 latency (milliseconds)"
  type        = number
  default     = 5000
  validation {
    condition     = var.alert_latency_p95_threshold_ms > 0
    error_message = "alert_latency_p95_threshold_ms must be greater than 0"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Tags
# ─────────────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
