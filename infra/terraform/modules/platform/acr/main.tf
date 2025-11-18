/// Module: platform/acr
/// Purpose: Azure Container Registry with optional private endpoint

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
    azuread = { source = "hashicorp/azuread" }
    http    = { source = "hashicorp/http" }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Data sources
# ─────────────────────────────────────────────────────────────────────────────

data "azuread_client_config" "current" {}

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

  # CAF-style ordering: workload - env - region - role - optional identifier
  suffix_components = compact([local.workload_code, local.env_code, local.region, "platform", local.identifier_code == "" ? null : local.identifier_code])

  common_tags = merge({
    project     = local.workload_code
    environment = local.env_code
    location    = local.region
    role        = "platform"
    managed_by  = "terraform"
  }, var.tags)

}

# ─────────────────────────────────────────────────────────────────────────────
# Naming (used when override not supplied)
# ─────────────────────────────────────────────────────────────────────────────

module "naming_acr" {
  source        = "Azure/naming/azurerm"
  version       = "0.4.2"
  suffix        = local.suffix_components
  unique-length = 6
}

# ─────────────────────────────────────────────────────────────────────────────
# Azure Container Registry
# ─────────────────────────────────────────────────────────────────────────────

module "acr" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "0.4.0"

  name                = var.acr_name_override != "" ? var.acr_name_override : module.naming_acr.container_registry.name_unique
  resource_group_name = var.resource_group_name
  location            = local.location_canonical

  sku                           = var.acr_sku
  admin_enabled                 = var.acr_admin_enabled
  public_network_access_enabled = var.public_network_access_enabled

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# RBAC - AcrPush for bootstrap SP
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_role_assignment" "bootstrap_acr_push" {
  scope                = module.acr.resource_id
  role_definition_name = "AcrPush"
  principal_id         = data.azuread_client_config.current.object_id
}
