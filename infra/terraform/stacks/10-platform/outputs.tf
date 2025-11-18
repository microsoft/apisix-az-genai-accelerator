output "location" {
  description = "Azure region where foundation resources reside"
  value       = var.location
}

output "platform_resource_group_name" {
  description = "Name of the platform resource group"
  value       = azurerm_resource_group.platform.name
}

output "platform_acr_name" {
  description = "Name of the platform Azure Container Registry"
  value       = module.platform_acr.acr_name
}

output "platform_acr_login_server" {
  description = "Login server of the platform ACR"
  value       = module.platform_acr.acr_login_server
}

output "platform_acr_id" {
  description = "Resource ID of the platform ACR"
  value       = module.platform_acr.acr_id
}

output "platform_acr_private_dns_zone_id" {
  description = "ID of the ACR private DNS zone (not created; deprecated output preserved for compatibility)"
  value       = null
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = module.key_vault.key_vault_name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = module.key_vault.key_vault_uri
}

output "key_vault_id" {
  description = "Resource ID of the Key Vault"
  value       = module.key_vault.key_vault_id
}

output "aca_managed_identity_id" {
  description = "ID of the ACA managed identity for Key Vault access"
  value       = module.key_vault.aca_managed_identity_id
}

output "aca_managed_identity_client_id" {
  description = "Client ID of the ACA managed identity for Key Vault access"
  value       = module.key_vault.aca_managed_identity_client_id
}

output "aca_managed_identity_principal_id" {
  description = "Principal ID of the ACA managed identity for Key Vault access"
  value       = module.key_vault.aca_managed_identity_principal_id
}
