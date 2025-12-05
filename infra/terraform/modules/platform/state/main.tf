/// Module: platform/state
/// Purpose: Remote state storage account, resource group, and RBAC

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
    azuread = { source = "hashicorp/azuread" }
    time    = { source = "hashicorp/time" }
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
  suffix_components = compact([local.workload_code, local.env_code, local.region, "tfstate", local.identifier_code == "" ? null : local.identifier_code])

  common_tags = merge({
    project     = local.workload_code
    environment = local.env_code
    location    = local.region
    role        = "state"
    managed_by  = "terraform"
  }, var.tags)

  state_container_name = "tfstate"
  state_blob_key       = "${local.env_code}/terraform.tfstate"

  allowed_ip_rules = [for ip in var.allowed_public_ip_addresses : ip]

  public_ip_network_rules = {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    ip_rules                   = local.allowed_ip_rules
    virtual_network_subnet_ids = []
    private_link_access        = null
  }

  computed_network_rules = length(local.allowed_ip_rules) > 0 ? local.public_ip_network_rules : null
}

# ─────────────────────────────────────────────────────────────────────────────
# Naming
# ─────────────────────────────────────────────────────────────────────────────

module "naming_state" {
  source        = "Azure/naming/azurerm"
  version       = "0.4.2"
  suffix        = local.suffix_components
  unique-length = 6
}

# ─────────────────────────────────────────────────────────────────────────────
# Resource Group
# ─────────────────────────────────────────────────────────────────────────────

module "state_rg" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.2.1"

  name     = var.state_rg_name_override != "" ? var.state_rg_name_override : module.naming_state.resource_group.name
  location = local.location_canonical
  tags     = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Storage Account
# ─────────────────────────────────────────────────────────────────────────────

module "state_sa" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.6.1"

  name                = module.naming_state.storage_account.name_unique
  location            = local.location_canonical
  resource_group_name = module.state_rg.name

  account_tier                  = "Standard"
  account_replication_type      = upper(var.sa_replication_type)
  account_kind                  = "StorageV2"
  https_traffic_only_enabled    = true
  min_tls_version               = "TLS1_2"
  public_network_access_enabled = true

  network_rules = local.computed_network_rules

  containers = {
    tfstate = {
      name                    = local.state_container_name
      container_access_type   = "private"
      delete_retention_policy = { days = var.soft_delete_retention_days }
    }
  }

  diagnostic_settings_storage_account = {}

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# RBAC & Wait
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_role_assignment" "state_sa_blob_contrib" {
  scope                = module.state_sa.resource_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azuread_client_config.current.object_id
}
