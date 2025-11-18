/// Stack: 15-openai
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

locals {
  foundation_outputs         = data.terraform_remote_state.foundation.outputs
  platform_resource_group    = try(local.foundation_outputs.platform_resource_group_name, null)
  platform_vnet_id           = try(local.foundation_outputs.platform_vnet_id, null)
  private_endpoint_subnet_id = try(local.foundation_outputs.private_endpoint_subnet_id, null)
  key_vault_id               = try(local.foundation_outputs.key_vault_id, null)
  key_vault_available        = local.key_vault_id != null && local.key_vault_id != ""
}

module "openai_private_dns_zone" {
  count  = local.deploy_openai && var.azure_openai_network_isolation && local.platform_vnet_id != null ? 1 : 0
  source = "../../modules/network/private_dns_zone"

  name                        = "privatelink.openai.azure.com"
  resource_group_name         = local.platform_resource_group
  virtual_networks_to_link_id = local.platform_vnet_id
  environment_code            = var.environment_code
  workload_name               = var.workload_name
  region_code                 = local.region_code
  identifier                  = var.identifier
  tags                        = merge(local.common_tags, { role = "openai-dns" })
}

module "azure_openai" {
  count  = local.deploy_openai ? length(local.openai_instances_with_defaults) : 0
  source = "../../modules/azure-ai-foundry"

  name = var.azure_openai_custom_subdomain_prefix != "" ? (
    "${var.azure_openai_custom_subdomain_prefix}-${local.openai_instances_with_defaults[count.index].name_suffix}"
    ) : (
    "openai-${local.workload_code}-${local.env_code}-${local.region_code}-${local.openai_instances_with_defaults[count.index].name_suffix}-${substr(sha256("${var.subscription_id}-${count.index}"), 0, 6)}"
  )
  resource_group_name = local.platform_resource_group
  location            = local.openai_instances_with_defaults[count.index].location
  sku_name            = local.openai_instances_with_defaults[count.index].sku_name
  custom_subdomain_name = var.azure_openai_custom_subdomain_prefix != "" ? (
    lower("${var.azure_openai_custom_subdomain_prefix}-${local.region_code}-${local.openai_instances_with_defaults[count.index].name_suffix}")
  ) : null
  public_network_access_enabled = local.openai_instances_with_defaults[count.index].public_network_access_enabled
  deployments                   = local.openai_instances_with_defaults[count.index].deployments
  environment_code              = var.environment_code
  workload_name                 = var.workload_name
  identifier                    = var.identifier
  instance_suffix               = local.openai_instances_with_defaults[count.index].name_suffix
  instance_index                = count.index
  enable_private_endpoint       = var.azure_openai_network_isolation && local.platform_vnet_id != null && local.private_endpoint_subnet_id != null
  private_dns_zone_id           = var.azure_openai_network_isolation && length(module.openai_private_dns_zone) > 0 ? module.openai_private_dns_zone[0].id : ""
  private_endpoint_subnet_id    = var.azure_openai_network_isolation && local.private_endpoint_subnet_id != null ? local.private_endpoint_subnet_id : ""
  private_endpoint_location     = var.azure_openai_network_isolation ? try(local.foundation_outputs.location, var.location) : null
  log_analytics_workspace_id    = var.log_analytics_workspace_id
  tags                          = local.common_tags
}
