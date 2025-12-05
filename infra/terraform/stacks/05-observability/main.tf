/// Stack: 05-observability
/// Purpose: Shared observability resources (Log Analytics, Azure Monitor workspace, App Insights, optional dashboard)

module "regions" {
  source          = "Azure/avm-utl-regions/azurerm"
  version         = "0.5.0"
  use_cached_data = true
}

locals {
  region_object      = lookup(module.regions.regions_by_name_or_display_name, lower(var.location), null)
  _validate_region   = local.region_object != null ? true : error("Invalid location '${var.location}'")
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

module "naming_obs_rg" {
  source        = "Azure/naming/azurerm"
  version       = "0.4.2"
  suffix        = compact(concat(local.suffix_base, ["obs", local.identifier_code == "" ? null : local.identifier_code]))
  unique-length = 6
}

resource "azurerm_resource_group" "observability" {
  name     = module.naming_obs_rg.resource_group.name
  location = local.location_canonical
  tags     = merge(local.common_tags, { role = "observability" })
}

# ─────────────────────────────────────────────────────────────────────────────
# Log Analytics Workspace
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_log_analytics_workspace" "main" {
  name                = module.naming_obs_rg.log_analytics_workspace.name_unique
  location            = local.location_canonical
  resource_group_name = azurerm_resource_group.observability.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = merge(local.common_tags, { role = "observability" })
}

# ─────────────────────────────────────────────────────────────────────────────
# Azure Monitor Workspace (Prometheus)
# ─────────────────────────────────────────────────────────────────────────────

module "azure_monitor_workspace" {
  source = "../../modules/azure-monitor/workspace"

  subscription_id               = var.subscription_id
  rg_name                       = azurerm_resource_group.observability.name
  location                      = local.location_canonical
  environment_code              = var.environment_code
  workload_name                 = var.workload_name
  identifier                    = var.identifier
  public_network_access_enabled = var.public_network_access_enabled
  tags                          = merge(local.common_tags, { role = "monitoring" })
}

# ─────────────────────────────────────────────────────────────────────────────
# Application Insights (workspace-based)
# ─────────────────────────────────────────────────────────────────────────────

module "naming_appi" {
  source        = "Azure/naming/azurerm"
  version       = "0.4.2"
  suffix        = compact(concat(local.suffix_base, ["appi", local.identifier_code == "" ? null : local.identifier_code]))
  unique-length = 6
}

resource "azurerm_application_insights" "main" {
  name                                = module.naming_appi.application_insights.name_unique
  location                            = local.location_canonical
  resource_group_name                 = azurerm_resource_group.observability.name
  workspace_id                        = azurerm_log_analytics_workspace.main.id
  application_type                    = "web"
  daily_data_cap_in_gb                = var.app_insights_daily_cap_gb
  internet_ingestion_enabled          = var.public_network_access_enabled
  internet_query_enabled              = var.public_network_access_enabled
  retention_in_days                   = var.log_retention_days
  force_customer_storage_for_profiler = false

  tags = merge(local.common_tags, { role = "observability" })
}

# ─────────────────────────────────────────────────────────────────────────────
# Optional Azure Portal dashboard placeholder
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_portal_dashboard" "observability" {
  count               = var.enable_dashboard ? 1 : 0
  name                = "dash-${local.workload_code}-${local.env_code}-${local.region_code}"
  resource_group_name = azurerm_resource_group.observability.name
  location            = local.location_canonical

  # Minimal starter dashboard – users can edit in Portal without breaking TF
  dashboard_properties = jsonencode({
    lenses = [
      {
        order = 0
        parts = [
          {
            position = {
              x       = 0
              y       = 0
              rowSpan = 2
              colSpan = 6
            }
            metadata = {
              type = "Extension/HubsExtension/PartType/MarkdownPart"
              settings = {
                content = {
                  settings = {
                    content = "# Observability\n- LAW: ${azurerm_log_analytics_workspace.main.name}\n- AMW: ${module.azure_monitor_workspace.workspace_name}\n- App Insights: ${azurerm_application_insights.main.name}"
                  }
                }
              }
            }
          }
        ]
      }
    ]
    metadata = {
      model = "v2"
    }
  })

  tags = merge(local.common_tags, { role = "observability" })
}

# ─────────────────────────────────────────────────────────────────────────────
# APISIX gateway log ingestion (shared)
# ─────────────────────────────────────────────────────────────────────────────

module "apim_gateway_logs" {
  count  = var.enable_gateway_log_ingestion ? 1 : 0
  source = "../../modules/azure-monitor/apim-gateway-logs"

  workspace_id        = azurerm_log_analytics_workspace.main.id
  location            = local.location_canonical
  resource_group_name = azurerm_resource_group.observability.name
  stream_name         = "Custom-APISIXGatewayLogs"
  custom_table_name   = "APISIXGatewayLogs_CL"
  dcr_name            = "dcr-apim-gw-logs-v3"
  tags                = merge(local.common_tags, { role = "observability" })
}
