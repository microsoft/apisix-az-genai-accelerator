/// Module: aca/alerts
/// Purpose: Azure Monitor alert rules and action groups for gateway monitoring

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
  }
}

module "regions" {
  source          = "Azure/avm-utl-regions/azurerm"
  version         = "0.5.0"
  use_cached_data = true
}

# ─────────────────────────────────────────────────────────────────────────────
# Locals
# ─────────────────────────────────────────────────────────────────────────────

locals {
  region_object    = lookup(module.regions.regions_by_name_or_display_name, lower(var.location), null)
  _validate_region = local.region_object != null ? true : error("Invalid location '${var.location}'")

  location_canonical = local.region_object.name
  region             = local.region_object.geo_code
  env_code           = lower(var.environment_code)
  workload_code      = lower(var.workload_name)
  identifier_code    = var.identifier != "" ? lower(var.identifier) : ""

  # Role last: workload-env-region-role
  suffix_base = compact([local.workload_code, local.env_code, local.region, "alerts", local.identifier_code == "" ? null : local.identifier_code])

  common_tags = merge({
    project     = local.workload_code
    environment = local.env_code
    location    = local.region
    managed_by  = "terraform"
    role        = "alerts"
  }, var.tags)

  alert_rule_suffixes = {
    high_5xx_rate    = "5xx"
    high_429_rate    = "429"
    high_latency_p95 = "lat"
    no_traffic       = "idle"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Naming
# ─────────────────────────────────────────────────────────────────────────────

module "naming_action_group" {
  source        = "Azure/naming/azurerm"
  version       = "0.4.2"
  suffix        = local.suffix_base
  unique-length = 6
}

module "naming_alert_rules" {
  for_each      = local.alert_rule_suffixes
  source        = "Azure/naming/azurerm"
  version       = "0.4.2"
  suffix        = concat(local.suffix_base, [each.value])
  unique-length = 6
}

# ─────────────────────────────────────────────────────────────────────────────
# Action Group for alert notifications
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_monitor_action_group" "gateway_alerts" {
  count = var.enable_alerts ? 1 : 0

  name                = module.naming_action_group.monitor_action_group.name_unique
  resource_group_name = var.rg_name
  short_name          = "gw-alerts"

  # Email notifications
  dynamic "email_receiver" {
    for_each = var.alert_email_receivers
    content {
      name                    = email_receiver.value.name
      email_address           = email_receiver.value.email
      use_common_alert_schema = true
    }
  }

  # Webhook notifications
  dynamic "webhook_receiver" {
    for_each = var.alert_webhook_receivers
    content {
      name                    = webhook_receiver.value.name
      service_uri             = webhook_receiver.value.uri
      use_common_alert_schema = true
    }
  }

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Alert Rule: High 5xx Error Rate
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "high_5xx_rate" {
  count = var.enable_alerts ? 1 : 0

  name                = module.naming_alert_rules["high_5xx_rate"].monitor_scheduled_query_rules_alert.name_unique
  resource_group_name = var.rg_name
  location            = local.location_canonical

  evaluation_frequency = "PT5M"  # Every 5 minutes
  window_duration      = "PT15M" # Over last 15 minutes
  scopes               = [var.law_id]
  severity             = 2 # Warning

  criteria {
    query = <<-QUERY
      ContainerAppConsoleLogs_CL
      | where ContainerAppName_s == "${var.gateway_app_name}"
      | where Log_s has "request_id"
      | extend LogJson = parse_json(Log_s)
      | extend Status = toint(LogJson.response.status)
      | summarize 
          TotalRequests = count(),
          ErrorRequests = countif(Status >= 500)
      | extend ErrorRate = (ErrorRequests * 100.0) / TotalRequests
      | where ErrorRate > ${var.alert_5xx_threshold_percent}
    QUERY

    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThan"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 2
      number_of_evaluation_periods             = 3
    }
  }

  auto_mitigation_enabled          = true
  workspace_alerts_storage_enabled = false
  description                      = "Alert when 5xx error rate exceeds ${var.alert_5xx_threshold_percent}% over 15 minutes"
  display_name                     = "Gateway: High 5xx Error Rate"
  enabled                          = true
  skip_query_validation            = false

  action {
    action_groups = [azurerm_monitor_action_group.gateway_alerts[0].id]
  }

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Alert Rule: High 429 Rate (Backend Throttling)
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "high_429_rate" {
  count = var.enable_alerts ? 1 : 0

  name                = module.naming_alert_rules["high_429_rate"].monitor_scheduled_query_rules_alert.name_unique
  resource_group_name = var.rg_name
  location            = local.location_canonical

  evaluation_frequency = "PT5M"
  window_duration      = "PT15M"
  scopes               = [var.law_id]
  severity             = 2 # Warning

  criteria {
    query = <<-QUERY
      ContainerAppConsoleLogs_CL
      | where ContainerAppName_s == "${var.gateway_app_name}"
      | where Log_s has "request_id"
      | extend LogJson = parse_json(Log_s)
      | extend Status = toint(LogJson.response.status)
      | summarize 
          TotalRequests = count(),
          ThrottledRequests = countif(Status == 429)
      | extend ThrottleRate = (ThrottledRequests * 100.0) / TotalRequests
      | where ThrottleRate > ${var.alert_429_threshold_percent}
    QUERY

    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThan"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 2
      number_of_evaluation_periods             = 3
    }
  }

  auto_mitigation_enabled          = true
  workspace_alerts_storage_enabled = false
  description                      = "Alert when 429 (throttled) rate exceeds ${var.alert_429_threshold_percent}% over 15 minutes"
  display_name                     = "Gateway: High Throttling Rate (429)"
  enabled                          = true
  skip_query_validation            = false

  action {
    action_groups = [azurerm_monitor_action_group.gateway_alerts[0].id]
  }

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Alert Rule: High Latency (P95)
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "high_latency_p95" {
  count = var.enable_alerts ? 1 : 0

  name                = module.naming_alert_rules["high_latency_p95"].monitor_scheduled_query_rules_alert.name_unique
  resource_group_name = var.rg_name
  location            = local.location_canonical

  evaluation_frequency = "PT5M"
  window_duration      = "PT15M"
  scopes               = [var.law_id]
  severity             = 3 # Informational

  criteria {
    query = <<-QUERY
      ContainerAppConsoleLogs_CL
      | where ContainerAppName_s == "${var.gateway_app_name}"
      | where Log_s has "request_id"
      | extend LogJson = parse_json(Log_s)
      | extend RequestTime = todouble(LogJson.request.time)
      | summarize P95 = percentile(RequestTime, 95)
      | where P95 > ${var.alert_latency_p95_threshold_ms}
    QUERY

    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThan"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 2
      number_of_evaluation_periods             = 3
    }
  }

  auto_mitigation_enabled          = true
  workspace_alerts_storage_enabled = false
  description                      = "Alert when P95 latency exceeds ${var.alert_latency_p95_threshold_ms}ms over 15 minutes"
  display_name                     = "Gateway: High Latency (P95)"
  enabled                          = true
  skip_query_validation            = false

  action {
    action_groups = [azurerm_monitor_action_group.gateway_alerts[0].id]
  }

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Alert Rule: No Traffic / Gateway Down
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "no_traffic" {
  count = var.enable_alerts ? 1 : 0

  name                = module.naming_alert_rules["no_traffic"].monitor_scheduled_query_rules_alert.name_unique
  resource_group_name = var.rg_name
  location            = local.location_canonical

  evaluation_frequency = "PT5M"
  window_duration      = "PT15M"
  scopes               = [var.law_id]
  severity             = 0 # Critical

  criteria {
    query = <<-QUERY
      ContainerAppConsoleLogs_CL
      | where ContainerAppName_s == "${var.gateway_app_name}"
      | where Log_s has "request_id"
      | summarize RequestCount = count()
      | where RequestCount == 0
    QUERY

    time_aggregation_method = "Count"
    threshold               = 1
    operator                = "GreaterThanOrEqual"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 3
      number_of_evaluation_periods             = 3
    }
  }

  auto_mitigation_enabled          = true
  workspace_alerts_storage_enabled = false
  description                      = "Alert when gateway receives no traffic for 15 minutes (potential outage)"
  display_name                     = "Gateway: No Traffic Detected"
  enabled                          = true
  skip_query_validation            = false

  action {
    action_groups = [azurerm_monitor_action_group.gateway_alerts[0].id]
  }

  tags = local.common_tags
}
