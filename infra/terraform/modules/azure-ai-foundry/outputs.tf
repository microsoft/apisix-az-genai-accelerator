output "resource_id" {
  description = "Resource ID of the Azure AI Foundry account"
  value       = module.cognitive_account.resource_id
}

output "endpoint" {
  description = "Endpoint URL of the Azure AI Foundry account"
  value       = module.cognitive_account.endpoint
}

output "primary_access_key" {
  description = "Primary access key for the account"
  value       = module.cognitive_account.primary_access_key
  sensitive   = true
}

output "system_assigned_identity_principal_id" {
  description = "Principal ID of the system-assigned managed identity"
  value       = module.cognitive_account.system_assigned_mi_principal_id
}
