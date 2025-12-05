output "gateway_identity_id" {
  description = "ID of the gateway user-assigned identity"
  value       = azurerm_user_assigned_identity.gateway.id
}

output "gateway_identity_principal_id" {
  description = "Principal ID of the gateway user-assigned identity"
  value       = azurerm_user_assigned_identity.gateway.principal_id
}

output "gateway_app_name" {
  description = "Name of the gateway Container App"
  value       = azurerm_container_app.gateway.name
}

output "gateway_app_id" {
  description = "ID of the gateway Container App"
  value       = azurerm_container_app.gateway.id
}

output "gateway_fqdn" {
  description = "FQDN of the gateway Container App"
  value       = azurerm_container_app.gateway.ingress[0].fqdn
}

output "gateway_url" {
  description = "Full URL of the gateway Container App"
  value       = "https://${azurerm_container_app.gateway.ingress[0].fqdn}"
}

output "gateway_outbound_ips" {
  description = "Outbound IP addresses of the gateway Container App"
  value       = azurerm_container_app.gateway.outbound_ip_addresses
}

output "acr_id" {
  description = "ID of the platform Container Registry"
  value       = var.platform_acr_id
}

output "acr_login_server" {
  description = "Login server of the platform Container Registry"
  value       = var.platform_acr_login
}

output "app_insights_connection_string" {
  description = "Application Insights connection string"
  value       = local.app_insights_connection_string
  sensitive   = true
}

output "app_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = length(azurerm_application_insights.this) > 0 ? azurerm_application_insights.this[0].instrumentation_key : ""
  sensitive   = true
}
