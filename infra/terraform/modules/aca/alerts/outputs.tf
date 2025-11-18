output "action_group_id" {
  description = "ID of the monitor action group (if created)"
  value       = var.enable_alerts ? azurerm_monitor_action_group.gateway_alerts[0].id : null
}

output "action_group_name" {
  description = "Name of the monitor action group (if created)"
  value       = var.enable_alerts ? azurerm_monitor_action_group.gateway_alerts[0].name : ""
}

output "alert_rule_ids" {
  description = "IDs of all created alert rules"
  value = var.enable_alerts ? {
    high_5xx_rate    = azurerm_monitor_scheduled_query_rules_alert_v2.high_5xx_rate[0].id
    high_429_rate    = azurerm_monitor_scheduled_query_rules_alert_v2.high_429_rate[0].id
    high_latency_p95 = azurerm_monitor_scheduled_query_rules_alert_v2.high_latency_p95[0].id
    no_traffic       = azurerm_monitor_scheduled_query_rules_alert_v2.no_traffic[0].id
  } : {}
}
