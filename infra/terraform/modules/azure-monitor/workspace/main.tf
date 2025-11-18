/// Module: azure-monitor/workspace
/// Purpose: Azure Monitor workspace for Prometheus metrics collection

terraform {
  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.27.0"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Data sources & locals
# ─────────────────────────────────────────────────────────────────────────────

module "regions" {
  source          = "Azure/avm-utl-regions/azurerm"
  version         = "0.5.0"
  use_cached_data = true
}

locals {
  region_object      = lookup(module.regions.regions_by_name_or_display_name, lower(var.location), null)
  _validate_region   = local.region_object != null ? true : error("Invalid location '${var.location}'")
  location_canonical = local.region_object.name
  region_short       = local.region_object.geo_code
  workload_code      = lower(var.workload_name)
  env_code           = lower(var.environment_code)
  identifier_code    = var.identifier != "" ? lower(var.identifier) : ""

  # Role last: workload-env-region-role
  suffix_components = compact([local.workload_code, local.env_code, local.region_short, "monitor", local.identifier_code == "" ? null : local.identifier_code])

  common_tags = merge(var.tags, {
    project     = local.workload_code
    environment = local.env_code
    location    = local.region_short
    managed_by  = "terraform"
    role        = "monitoring"
  })
}

module "naming_monitor" {
  source        = "Azure/naming/azurerm"
  version       = "0.4.2"
  suffix        = local.suffix_components
  unique-length = 6
}

# ─────────────────────────────────────────────────────────────────────────────
# Azure Monitor Workspace
# ─────────────────────────────────────────────────────────────────────────────

resource "azapi_resource" "workspace" {
  type      = "Microsoft.Monitor/accounts@2023-04-03"
  name      = replace(module.naming_monitor.application_insights.name_unique, "appi-", "azmon-")
  location  = local.location_canonical
  parent_id = "/subscriptions/${var.subscription_id}/resourceGroups/${var.rg_name}"

  body = {
    properties = {
      publicNetworkAccess = var.public_network_access_enabled ? "Enabled" : "Disabled"
    }
  }

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Default ingestion resources (Data Collection Endpoint & Rule)
# ─────────────────────────────────────────────────────────────────────────────

data "azapi_resource" "default_dce" {
  type        = "Microsoft.Insights/dataCollectionEndpoints@2023-03-11"
  resource_id = azapi_resource.workspace.output.properties.defaultIngestionSettings.dataCollectionEndpointResourceId

  depends_on = [azapi_resource.workspace]
}

data "azapi_resource" "default_dcr" {
  type        = "Microsoft.Insights/dataCollectionRules@2023-03-11"
  resource_id = azapi_resource.workspace.output.properties.defaultIngestionSettings.dataCollectionRuleResourceId

  depends_on = [azapi_resource.workspace]
}

locals {
  metrics_ingest_endpoint = try(data.azapi_resource.default_dce.output.properties.metricsIngestion.endpoint, "")
  dcr_immutable_id        = try(data.azapi_resource.default_dcr.output.properties.immutableId, "")
  prometheus_remote_write_base = (
    local.metrics_ingest_endpoint != "" && local.dcr_immutable_id != ""
  ) ? "${local.metrics_ingest_endpoint}/dataCollectionRules/${local.dcr_immutable_id}/streams/Microsoft-PrometheusMetrics" : ""
}
