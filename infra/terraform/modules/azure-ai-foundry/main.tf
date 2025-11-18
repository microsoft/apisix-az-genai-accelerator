locals {
  account_tags = merge(var.tags, {
    role     = "openai"
    instance = var.instance_suffix
  })

  private_endpoint_tags = merge(var.tags, {
    role     = "openai-pe"
    instance = var.instance_suffix
  })

  diagnostic_settings = var.log_analytics_workspace_id == "" ? {} : {
    openai = {
      workspace_resource_id = var.log_analytics_workspace_id
      log_categories        = toset(["Audit", "RequestResponse"])
      metric_categories     = toset(["AllMetrics"])
    }
  }

  private_endpoint_identifier = var.identifier != "" ? "${var.identifier}-openai-${var.instance_index}" : "openai-${var.instance_index}"
}

module "cognitive_account" {
  source  = "Azure/avm-res-cognitiveservices-account/azurerm"
  version = "0.10.1"

  kind                = "OpenAI"
  location            = var.location
  name                = var.name
  resource_group_name = var.resource_group_name
  sku_name            = var.sku_name

  allow_project_management      = var.allow_project_management
  custom_subdomain_name         = var.custom_subdomain_name
  public_network_access_enabled = var.public_network_access_enabled
  diagnostic_settings           = local.diagnostic_settings
  managed_identities = {
    system_assigned = true
  }

  cognitive_deployments = { for deployment in var.deployments : deployment.name => {
    name                       = deployment.name
    dynamic_throttling_enabled = try(deployment.dynamic_throttling_enabled, false)
    version_upgrade_option     = try(deployment.version_upgrade_option, "OnceNewDefaultVersionAvailable")
    model = {
      format  = "OpenAI"
      name    = deployment.model.name
      version = deployment.model.version
    }
    scale = {
      type     = try(deployment.scale_type, "Standard")
      capacity = try(deployment.capacity, 1)
    }
  } }

  enable_telemetry = false
  tags             = local.account_tags
}

module "private_endpoint" {
  count  = var.enable_private_endpoint ? 1 : 0
  source = "../network/private_endpoint"

  resource_group_name            = var.resource_group_name
  private_connection_resource_id = module.cognitive_account.resource_id
  location                       = coalesce(var.private_endpoint_location, var.location)
  environment_code               = var.environment_code
  workload_name                  = var.workload_name
  identifier                     = local.private_endpoint_identifier
  subnet_id                      = var.private_endpoint_subnet_id
  is_manual_connection           = false
  subresource_name               = "account"
  private_dns_zone_group_ids     = var.private_dns_zone_id != "" ? [var.private_dns_zone_id] : []
  tags                           = local.private_endpoint_tags
}
