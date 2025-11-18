output "azure_openai_endpoints" {
  description = "Provisioned Azure OpenAI endpoints with metadata"
  value = [
    for idx, instance in module.azure_openai : {
      index    = idx
      endpoint = instance.endpoint
      host     = replace(instance.endpoint, "https://", "")
      location = try(local.openai_instances_with_defaults[idx].location, var.location)
      priority = try(local.openai_instances_with_defaults[idx].priority, 5)
      weight   = try(local.openai_instances_with_defaults[idx].weight, 1)
    }
  ]
}

output "azure_openai_key_vault_secret_names" {
  description = "Key Vault secret names for Azure AI Foundry API keys"
  value = local.key_vault_available ? [
    for idx in range(length(module.azure_openai)) : "azure-openai-primary-key-${idx}"
  ] : []
}

output "azure_openai_resource_ids" {
  description = "Azure AI Foundry resource IDs"
  value = [
    for instance in module.azure_openai : instance.resource_id
  ]
}

output "azure_openai_count" {
  description = "Number of provisioned Azure OpenAI instances"
  value       = length(module.azure_openai)
}

output "azure_openai_primary_keys" {
  description = "Primary access keys for Azure AI Foundry instances"
  value = [
    for instance in module.azure_openai : instance.primary_access_key
  ]
  sensitive = true
}
