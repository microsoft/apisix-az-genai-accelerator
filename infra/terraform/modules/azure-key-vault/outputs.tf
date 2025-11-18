output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "aca_managed_identity_id" {
  description = "ID of the ACA managed identity for Key Vault access"
  value       = azurerm_user_assigned_identity.aca_keyvault_identity.id
}

output "aca_managed_identity_client_id" {
  description = "Client ID of the ACA managed identity for Key Vault access"
  value       = azurerm_user_assigned_identity.aca_keyvault_identity.client_id
}

output "aca_managed_identity_principal_id" {
  description = "Principal ID of the ACA managed identity for Key Vault access"
  value       = azurerm_user_assigned_identity.aca_keyvault_identity.principal_id
}

output "private_endpoint_ip" {
  description = "Private IP address of the Key Vault private endpoint (null if no private endpoint)"
  value       = length(azurerm_private_endpoint.key_vault) > 0 ? azurerm_private_endpoint.key_vault[0].private_service_connection[0].private_ip_address : null
}

output "private_endpoint_fqdn" {
  description = "Private FQDN of the Key Vault"
  value       = "${azurerm_key_vault.main.name}.vault.azure.net"
}
