output "state_rg_name" {
  description = "Name of the state resource group"
  value       = module.state_rg.name
}

output "state_rg_id" {
  description = "ID of the state resource group"
  value       = module.state_rg.resource_id
}

output "storage_account_name" {
  description = "Name of the state storage account"
  value       = module.state_sa.name
}

output "storage_account_id" {
  description = "ID of the state storage account"
  value       = module.state_sa.resource_id
}

output "state_container_name" {
  description = "Name of the Terraform state container"
  value       = local.state_container_name
}

output "state_blob_key" {
  description = "Blob key for Terraform state file"
  value       = local.state_blob_key
}

output "backend_snippet" {
  description = "Backend configuration snippet for remote state"
  value       = <<EOT
use_azuread_auth     = true
tenant_id            = "${var.tenant_id}"
storage_account_name = "${module.state_sa.name}"
container_name       = "${local.state_container_name}"
key                  = "${local.state_blob_key}"
EOT
}

output "private_endpoint_id" {
  description = "ID of the private endpoint (if created)"
  value       = var.enable_state_sa_private_endpoint ? module.pe_state_sa[0].resource_id : null
}
