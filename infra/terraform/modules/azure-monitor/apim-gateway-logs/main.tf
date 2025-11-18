/// Module: azure-monitor/apim-gateway-logs
/// Purpose: Provide a Log Ingestion (DCE + DCR) path that accepts APIM gateway logs

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

locals {
  dce_name_default = var.dce_name != "" ? var.dce_name : "dce-apim-gw-logs"
  dcr_name_default = var.dcr_name != "" ? var.dcr_name : "dcr-apim-gw-logs"
  is_custom_stream = can(regex("^Custom-", var.stream_name))
  custom_table_name = local.is_custom_stream ? (
    var.custom_table_name != "" ? var.custom_table_name : "${replace(var.stream_name, "Custom-", "")}_CL"
  ) : ""
  custom_stream_columns = [
    { name = "TimeGenerated", type = "datetime" },
    { name = "OperationName", type = "string" },
    { name = "ApiId", type = "string" },
    { name = "ProductId", type = "string" },
    { name = "SubscriptionId", type = "string" },
    { name = "BackendId", type = "string" },
    { name = "ResponseCode", type = "int" },
    { name = "BackendResponseCode", type = "int" },
    { name = "TotalTime", type = "long" },
    { name = "BackendTime", type = "long" },
    { name = "Method", type = "string" },
    { name = "Url", type = "string" },
    { name = "GatewayId", type = "string" },
    { name = "CallerIpAddress", type = "string" },
    { name = "CorrelationId", type = "string" },
    { name = "RequestId", type = "string" },
    { name = "RequestHeaders", type = "dynamic" },
    { name = "ResponseHeaders", type = "dynamic" },
    { name = "RequestBody", type = "dynamic" },
  ]
}

resource "azurerm_monitor_data_collection_endpoint" "this" {
  name                          = local.dce_name_default
  location                      = var.location
  resource_group_name           = var.resource_group_name
  public_network_access_enabled = true
  tags                          = var.tags
}

resource "azurerm_monitor_data_collection_rule" "this" {
  name                        = local.dcr_name_default
  location                    = var.location
  resource_group_name         = var.resource_group_name
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.this.id
  depends_on                  = [azapi_resource.custom_table]

  destinations {
    log_analytics {
      workspace_resource_id = var.workspace_id
      name                  = "law"
    }
  }

  dynamic "data_flow" {
    for_each = local.is_custom_stream ? [true] : []
    content {
      streams       = [var.stream_name]
      destinations  = ["law"]
      output_stream = "Custom-${local.custom_table_name}"
    }
  }

  dynamic "data_flow" {
    for_each = local.is_custom_stream ? [] : [true]
    content {
      streams      = [var.stream_name]
      destinations = ["law"]
    }
  }

  dynamic "stream_declaration" {
    for_each = local.is_custom_stream ? { (var.stream_name) = true } : {}
    content {
      stream_name = stream_declaration.key
      dynamic "column" {
        for_each = local.custom_stream_columns
        content {
          name = column.value.name
          type = column.value.type
        }
      }
    }
  }

  tags = var.tags
}

resource "azapi_resource" "custom_table" {
  count = local.is_custom_stream ? 1 : 0

  type      = "Microsoft.OperationalInsights/workspaces/tables@2022-10-01"
  name      = local.custom_table_name
  parent_id = var.workspace_id
  schema_validation_enabled = false

  body = {
    properties = {
      plan                 = "Analytics"
      retentionInDays      = 30
      totalRetentionInDays = 30
      schema = {
        name         = local.custom_table_name
        columns      = local.custom_stream_columns
        tableType    = "CustomLog"
        tableSubType = "DataCollectionRuleBased"
      }
    }
  }
}

locals {
  ingest_uri = "${azurerm_monitor_data_collection_endpoint.this.logs_ingestion_endpoint}/dataCollectionRules/${azurerm_monitor_data_collection_rule.this.immutable_id}/streams/${var.stream_name}?api-version=2023-01-01"
}
