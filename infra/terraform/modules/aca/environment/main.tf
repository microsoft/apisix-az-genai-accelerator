/// Module: aca/environment
/// Purpose: Resource group, Log Analytics workspace, and Container Apps Environment

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Data sources
# ─────────────────────────────────────────────────────────────────────────────

module "regions" {
  source          = "Azure/avm-utl-regions/azurerm"
  version         = "0.5.0"
  use_cached_data = true
}

# ─────────────────────────────────────────────────────────────────────────────
# Locals
# ─────────────────────────────────────────────────────────────────────────────

locals {
  region_object    = lookup(module.regions.regions_by_name_or_display_name, lower(var.location), null)
  _validate_region = local.region_object != null ? true : error("Invalid location '${var.location}'")

  location_canonical = local.region_object.name
  env_code           = lower(var.environment_code)
  workload_code      = lower(var.workload_name)
  identifier_code    = var.identifier != "" ? lower(var.identifier) : ""
  region             = local.region_object.geo_code

  common_tags = merge({
    project     = local.workload_code
    environment = local.env_code
    location    = local.region
    role        = "workload"
    managed_by  = "terraform"
  }, var.tags)

  # Use provided workspace ID or create new one
  law_id = var.log_analytics_workspace_id != "" ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.this[0].id
}

# ─────────────────────────────────────────────────────────────────────────────
# Naming
# ─────────────────────────────────────────────────────────────────────────────

module "naming" {
  source        = "Azure/naming/azurerm"
  version       = "0.4.2"
  # Role last: workload-env-region-role
  suffix        = compact([local.workload_code, local.env_code, local.region, "workload", local.identifier_code == "" ? null : local.identifier_code])
  unique-length = 6
}

# ─────────────────────────────────────────────────────────────────────────────
# Resource Group
# ─────────────────────────────────────────────────────────────────────────────

module "rg" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.2.1"

  name     = var.rg_name_override != "" ? var.rg_name_override : module.naming.resource_group.name
  location = local.location_canonical
  tags     = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Log Analytics Workspace (optional)
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_log_analytics_workspace" "this" {
  count = var.log_analytics_workspace_id == "" ? 1 : 0

  name                = module.naming.log_analytics_workspace.name_unique
  resource_group_name = module.rg.name
  location            = local.location_canonical
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Container Apps Environment
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_container_app_environment" "this" {
  name                       = var.aca_env_name_override != "" ? var.aca_env_name_override : module.naming.container_app_environment.name
  location                   = local.location_canonical
  resource_group_name        = module.rg.name
  log_analytics_workspace_id = local.law_id

  tags = local.common_tags
}
