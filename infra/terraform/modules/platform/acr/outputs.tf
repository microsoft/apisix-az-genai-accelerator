output "acr_id" {
  description = "ID of the Azure Container Registry (null if not created)"
  value       = module.acr.resource_id
}

output "acr_name" {
  description = "Name of the Azure Container Registry (empty if not created)"
  value       = module.acr.name
}

output "acr_login_server" {
  description = "Login server of the Azure Container Registry (empty if not created)"
  value       = module.acr.resource.login_server
}

output "resource_group_name" {
  description = "Resource group where the ACR resides"
  value       = var.resource_group_name
}
