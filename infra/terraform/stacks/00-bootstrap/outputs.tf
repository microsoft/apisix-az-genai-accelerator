output "backend_snippet" {
  description = "Backend configuration snippet for remote state"
  value       = module.state.backend_snippet
}

output "location" {
  description = "Azure region where resources are deployed"
  value       = var.location
}

output "state_rg_name" {
  description = "Name of the state resource group"
  value       = module.state.state_rg_name
}

output "storage_account_name" {
  description = "Name of the state storage account"
  value       = module.state.storage_account_name
}

output "state_container_name" {
  description = "Name of the Terraform state container"
  value       = module.state.state_container_name
}

output "state_blob_key" {
  description = "Blob key for Terraform state"
  value       = module.state.state_blob_key
}
