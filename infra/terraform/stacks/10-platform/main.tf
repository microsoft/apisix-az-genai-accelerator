/// Stack: 10-platform
/// Purpose: Shared platform resources (resource groups, networking, ACR, secrets)

module "regions" {
  source          = "Azure/avm-utl-regions/azurerm"
  version         = "0.5.0"
  use_cached_data = true
}

locals {
  region_object      = lookup(module.regions.regions_by_name_or_display_name, lower(var.location), null)
  location_canonical = local.region_object.name
  region_code        = local.region_object.geo_code
  env_code           = lower(var.environment_code)
  workload_code      = lower(var.workload_name)
  identifier_code    = var.identifier != "" ? lower(var.identifier) : ""

  # CAF-style ordering: workload - env - region - role - optional identifier
  suffix_base = compact([local.workload_code, local.env_code, local.region_code])

  common_tags = merge({
    project     = local.workload_code
    environment = local.env_code
    location    = local.region_code
    managed_by  = "terraform"
  }, var.tags)
}

module "naming_platform_rg" {
  source        = "Azure/naming/azurerm"
  version       = "0.4.2"
  suffix        = compact(concat(local.suffix_base, ["platform", local.identifier_code == "" ? null : local.identifier_code]))
  unique-length = 6
}

module "naming_acr_diag" {
  source        = "Azure/naming/azurerm"
  version       = "0.4.2"
  suffix        = compact(concat(local.suffix_base, ["acr", "diag", local.identifier_code == "" ? null : local.identifier_code]))
  unique-length = 6
}

# Discover caller public IP (used only when enabling KV IP allowlist for tests)
module "public_ip" {
  source = "github.com/lonegunmanb/terraform-lonegunmanb-public-ip?ref=v0.1.0"
}

# ─────────────────────────────────────────────────────────────────────────────
# Resource groups
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_resource_group" "platform" {
  name     = var.platform_rg_name_override != "" ? var.platform_rg_name_override : module.naming_platform_rg.resource_group.name
  location = local.location_canonical
  tags     = merge(local.common_tags, { role = "platform" })

  lifecycle {
    precondition {
      condition     = local.region_object != null
      error_message = "Invalid location '${var.location}'"
    }
  }
}

# Azure Container Registry (shared platform registry)
# ─────────────────────────────────────────────────────────────────────────────

module "platform_acr" {
  source = "../../modules/platform/acr"

  resource_group_name           = azurerm_resource_group.platform.name
  environment_code              = var.environment_code
  location                      = var.location
  workload_name                 = var.workload_name
  identifier                    = var.identifier
  acr_name_override             = var.acr_name_override
  acr_sku                       = var.acr_sku
  acr_admin_enabled             = var.acr_admin_enabled
  public_network_access_enabled = true
  log_analytics_workspace_id    = var.log_analytics_workspace_id
  tags                          = merge(local.common_tags, { role = "platform" })
}

resource "azurerm_monitor_diagnostic_setting" "acr" {
  count = var.log_analytics_workspace_id == "" ? 0 : 1

  name                       = module.naming_acr_diag.monitor_diagnostic_setting.name_unique
  target_resource_id         = module.platform_acr.acr_id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }

  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Secret management (Key Vault + managed identity)
# ─────────────────────────────────────────────────────────────────────────────

module "key_vault" {
  source = "../../modules/azure-key-vault"

  workload_name           = var.workload_name
  environment             = var.environment_code
  identifier              = var.identifier
  location                = var.location
  resource_group_name     = azurerm_resource_group.platform.name
  key_vault_name_override = var.key_vault_name_override
  identity_name_override  = var.key_vault_identity_name_override
  tenant_id               = var.tenant_id
  subnet_id               = null
  private_dns_zone_id     = null
  purge_protection_enabled = var.key_vault_purge_protection_enabled
  deployment_principal_id = var.deployment_principal_id
  ip_rules                = var.enable_key_vault_public_ip_allowlist && module.public_ip.public_ip != "" ? [module.public_ip.public_ip] : []
  tags                    = local.common_tags
}
