output "location" {
  description = "Azure region for observability resources"
  value       = var.location
}

output "observability_rg_name" {
  description = "Resource group name for observability assets"
  value       = azurerm_resource_group.observability.name
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  description = "Log Analytics workspace name"
  value       = azurerm_log_analytics_workspace.main.name
}

output "app_insights_id" {
  description = "Application Insights resource ID"
  value       = azurerm_application_insights.main.id
}

output "app_insights_connection_string" {
  description = "Application Insights connection string"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "app_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "azure_monitor_workspace_id" {
  description = "Azure Monitor workspace (Prometheus) resource ID"
  value       = module.azure_monitor_workspace.workspace_id
}

output "azure_monitor_prometheus_remote_write_endpoint" {
  description = "Prometheus remote write endpoint base URL"
  value       = module.azure_monitor_workspace.prometheus_remote_write_endpoint
}

output "azure_monitor_prometheus_query_endpoint" {
  description = "Prometheus query endpoint URL"
  value       = module.azure_monitor_workspace.prometheus_query_endpoint
}

output "azure_monitor_prometheus_dcr_id" {
  description = "Default data collection rule resource ID for Prometheus ingestion"
  value       = module.azure_monitor_workspace.prometheus_data_collection_rule_id
}

output "gateway_logs_dce_id" {
  description = "Data Collection Endpoint ID for gateway logs (if enabled)"
  value       = length(module.apim_gateway_logs) > 0 ? module.apim_gateway_logs[0].dce_id : null
}

output "gateway_logs_dcr_id" {
  description = "Data Collection Rule ID for gateway logs (if enabled)"
  value       = length(module.apim_gateway_logs) > 0 ? module.apim_gateway_logs[0].dcr_id : null
}

output "gateway_logs_ingest_uri" {
  description = "Logs ingest URI for APISIX gateway logs (if enabled)"
  value       = length(module.apim_gateway_logs) > 0 ? module.apim_gateway_logs[0].ingest_uri : null
}

output "gateway_logs_stream_name" {
  description = "Stream name used for gateway log ingestion"
  value       = length(module.apim_gateway_logs) > 0 ? module.apim_gateway_logs[0].stream_name : null
}

output "gateway_logs_table_name" {
  description = "Custom table name for gateway logs"
  value       = length(module.apim_gateway_logs) > 0 ? module.apim_gateway_logs[0].custom_table_name : null
}
