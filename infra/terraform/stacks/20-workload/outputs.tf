output "gateway_url" {
  description = "Full URL of the gateway Container App"
  value       = module.gateway.gateway_url
}

output "gateway_fqdn" {
  description = "FQDN of the gateway Container App"
  value       = module.gateway.gateway_fqdn
}

output "gateway_app_name" {
  description = "Name of the gateway Container App"
  value       = module.gateway.gateway_app_name
}

output "responses_affinity_cache_fqdn" {
  description = "Internal FQDN of the responses affinity cache"
  value       = azurerm_container_app.responses_affinity_cache.ingress[0].fqdn
}

output "acr_login_server" {
  description = "Login server of the Container Registry"
  value       = module.gateway.acr_login_server
}

output "resource_group_name" {
  description = "Name of the ACA resource group"
  value       = module.env.rg_name
}

output "aca_environment_name" {
  description = "Name of the Container Apps environment"
  value       = module.env.aca_env_name
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = module.env.law_id
}

output "app_insights_connection_string" {
  description = "Application Insights connection string"
  value       = module.gateway.app_insights_connection_string
  sensitive   = true
}


output "alert_action_group_id" {
  description = "ID of the alert action group (if created)"
  value       = var.enable_alerts ? module.alerts[0].action_group_id : null
}

output "azure_monitor_workspace_id" {
  description = "Azure Monitor workspace ID"
  value       = local.azure_monitor_workspace_id
}

output "azure_monitor_prometheus_endpoint" {
  description = "Azure Monitor Prometheus remote-write base endpoint (without /api/v1/write)"
  value       = local.azure_monitor_prometheus_endpoint
}

output "azure_monitor_prometheus_query_endpoint" {
  description = "Azure Monitor Prometheus query endpoint"
  value       = local.azure_monitor_prometheus_query_endpoint
}

# Simulator outputs (present when gateway_e2e_test_mode=true)
output "simulator_api_key" {
  description = "Simulator API key configured in test mode"
  value       = var.simulator_api_key
  sensitive   = true
}

output "simulator_ptu1_fqdn" {
  description = "Simulator PTU1 FQDN (test mode)"
  value       = var.gateway_e2e_test_mode ? "https://${local.sim_ptu1_name}.${module.env.default_domain}" : null
}

output "simulator_payg1_fqdn" {
  description = "Simulator PAYG1 FQDN (test mode)"
  value       = var.gateway_e2e_test_mode ? "https://${local.sim_payg1_name}.${module.env.default_domain}" : null
}

output "simulator_payg2_fqdn" {
  description = "Simulator PAYG2 FQDN (test mode)"
  value       = var.gateway_e2e_test_mode ? "https://${local.sim_payg2_name}.${module.env.default_domain}" : null
}

output "key_vault_name" {
  description = "Key Vault backing the gateway secrets"
  value       = var.key_vault_name
}

output "secret_names" {
  description = "Resolved list of secret names mounted into the gateway"
  value       = local.final_secret_names
}
