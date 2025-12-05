output "azure_openai_endpoints" {
  description = "Provisioned Azure OpenAI endpoints with metadata"
  value = [
    for idx in sort(keys(local.ai_foundry_instances)) : {
      index    = tonumber(idx)
      endpoint = "https://${module.ai_foundry[idx].ai_foundry_name}.services.ai.azure.com"
      host     = "${module.ai_foundry[idx].ai_foundry_name}.services.ai.azure.com"
      location = try(local.ai_foundry_instances[idx].location, var.location)
      priority = try(local.ai_foundry_instances[idx].priority, 5)
      weight   = try(local.ai_foundry_instances[idx].weight, 1)
    }
  ]
}

output "azure_openai_key_vault_secret_names" {
  description = "Key Vault secret names for Azure AI Foundry API keys"
  value = local.key_vault_available ? [
    for idx in sort(keys(module.ai_foundry)) : "azure-openai-primary-key-${idx}"
  ] : []
}

output "azure_openai_resource_ids" {
  description = "Azure AI Foundry resource IDs"
  value = [
    for idx in sort(keys(module.ai_foundry)) : module.ai_foundry[idx].ai_foundry_id
  ]
}

output "azure_openai_count" {
  description = "Number of provisioned Azure OpenAI instances"
  value       = length(module.ai_foundry)
}

output "azure_openai_primary_keys" {
  description = "Primary access keys for Azure AI Foundry instances"
  value = [
    for idx in sort(keys(azapi_resource_action.ai_foundry_keys)) : azapi_resource_action.ai_foundry_keys[idx].output.key1
  ]
  sensitive = true
}
