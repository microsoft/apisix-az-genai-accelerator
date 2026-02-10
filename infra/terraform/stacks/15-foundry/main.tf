/// Stack: 15-foundry
/// Purpose: Provision Azure OpenAI (Foundry) instances after foundation stack completion

module "regions" {
  source          = "Azure/avm-utl-regions/azurerm"
  version         = "0.5.0"
  use_cached_data = true
}

locals {
  region_object    = lookup(module.regions.regions_by_name_or_display_name, lower(var.location), null)
  _validate_region = local.region_object != null ? true : error("Invalid location '${var.location}'")

  location_canonical = local.region_object.name
  region_code        = local.region_object.geo_code
  env_code           = lower(var.environment_code)
  workload_code      = lower(var.workload_name)
  identifier_code    = var.identifier != "" ? lower(var.identifier) : ""

  suffix_base = compact([local.workload_code, local.env_code, local.region_code, local.identifier_code == "" ? null : local.identifier_code])

  common_tags = merge({
    project     = local.workload_code
    environment = local.env_code
    location    = local.region_code
    managed_by  = "terraform"
  }, var.tags)

  deploy_openai = length(var.azure_openai_instances) > 0

  openai_instances_with_defaults = [
    for idx, instance in var.azure_openai_instances : merge({
      name_suffix                   = "instance-${idx}"
      location                      = var.location
      sku_name                      = "S0"
      priority                      = 5
      weight                        = 1
      public_network_access_enabled = var.azure_openai_network_isolation ? false : true
      deployments                   = []
    }, instance)
  ]

  ai_foundry_base_name = (
    length(replace("${local.workload_code}${local.env_code}${local.region_code}", "-", "")) >= 3
  ) ? substr(replace("${local.workload_code}${local.env_code}${local.region_code}", "-", ""), 0, 7) : "aif${substr(local.region_code, 0, 3)}"

  ai_foundry_instances = {
    for idx, instance in local.openai_instances_with_defaults : tostring(idx) => merge(instance, {
      location      = coalesce(instance.location, var.location)
      resource_name = var.azure_openai_custom_subdomain_prefix != "" ? "${var.azure_openai_custom_subdomain_prefix}-${local.region_code}-${instance.name_suffix}" : "aif-${local.workload_code}-${local.env_code}-${local.region_code}-${instance.name_suffix}"
      model_deployments = {
        for dep in instance.deployments : dep.name => {
          name                   = dep.name
          rai_policy_name        = dep.rai_policy_name
          version_upgrade_option = dep.version_upgrade_option
          model = {
            format  = "OpenAI"
            name    = dep.model.name
            version = dep.model.version
          }
          scale = {
            type     = dep.scale_type
            capacity = dep.capacity
            family   = null
            size     = null
            tier     = null
          }
        }
      }
    })
  }

}

data "terraform_remote_state" "foundation" {
  backend = "azurerm"
  config = {
    use_azuread_auth     = true
    tenant_id            = var.tenant_id
    resource_group_name  = var.remote_state_resource_group_name
    storage_account_name = var.remote_state_storage_account_name
    container_name       = var.remote_state_container_name
    key                  = var.foundation_state_blob_key
  }
}

data "azurerm_resource_group" "platform" {
  name = local.platform_resource_group
}

locals {
  foundation_outputs         = data.terraform_remote_state.foundation.outputs
  platform_resource_group    = try(local.foundation_outputs.platform_resource_group_name, null)
  platform_vnet_id           = try(local.foundation_outputs.platform_vnet_id, null)
  private_endpoint_subnet_id = try(local.foundation_outputs.private_endpoint_subnet_id, null)
  key_vault_id               = try(local.foundation_outputs.key_vault_id, null)
  key_vault_available        = local.key_vault_id != null && local.key_vault_id != ""
}

module "ai_foundry" {
  for_each = local.deploy_openai ? local.ai_foundry_instances : {}

  source  = "Azure/avm-ptn-aiml-ai-foundry/azurerm"
  version = "0.7.0"

  base_name                  = local.ai_foundry_base_name
  location                   = each.value.location
  resource_group_resource_id = data.azurerm_resource_group.platform.id

  ai_foundry = {
    name                     = each.value.resource_name
    allow_project_management = true
    create_ai_agent_service  = false
    # Enforce Entra ID-only data-plane access (no key-based local auth).
    disable_local_auth       = true
    sku                      = each.value.sku_name
  }

  ai_projects = {
    default = {
      name                       = "proj-${local.env_code}-${each.value.name_suffix}"
      sku                        = "S0"
      display_name               = "proj-${var.workload_name}-${var.environment_code}"
      description                = "Default AI project for ${var.workload_name} ${var.environment_code}"
      create_project_connections = false
      cosmos_db_connection       = {}
      ai_search_connection       = {}
      key_vault_connection       = {}
      storage_account_connection = {}
    }
  }

  ai_model_deployments = each.value.model_deployments

  # Only Foundry account + project + model deployments; skip KV/Storage/Cosmos/AI Search
  create_byor                         = false
  create_private_endpoints            = var.azure_openai_network_isolation && local.private_endpoint_subnet_id != null
  private_endpoint_subnet_resource_id = var.azure_openai_network_isolation ? local.private_endpoint_subnet_id : null
  tags                                = merge(local.common_tags, { role = "foundry", instance = each.value.name_suffix })
}

resource "azapi_resource_action" "ai_foundry_keys" {
  for_each = module.ai_foundry

  type                   = "Microsoft.CognitiveServices/accounts@2024-10-01"
  resource_id            = each.value.ai_foundry_id
  action                 = "listKeys"
  method                 = "POST"
  response_export_values = ["key1", "key2"]
}
