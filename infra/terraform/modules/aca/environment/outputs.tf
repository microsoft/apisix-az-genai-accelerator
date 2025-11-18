output "rg_name" {
  description = "Name of the resource group"
  value       = module.rg.name
}

output "rg_id" {
  description = "ID of the resource group"
  value       = module.rg.resource_id
}

output "law_id" {
  description = "ID of the Log Analytics workspace"
  value       = local.law_id
}

output "aca_env_id" {
  description = "ID of the Container Apps environment"
  value       = azurerm_container_app_environment.this.id
}

output "aca_env_name" {
  description = "Name of the Container Apps environment"
  value       = azurerm_container_app_environment.this.name
}

output "default_domain" {
  description = "Default domain of the Container Apps environment"
  value       = azurerm_container_app_environment.this.default_domain
}
