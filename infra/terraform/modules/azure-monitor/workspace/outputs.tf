/// Outputs for Azure Monitor workspace module

output "workspace_id" {
  description = "The resource ID of the Azure Monitor workspace"
  value       = azapi_resource.workspace.id
}

output "workspace_name" {
  description = "The name of the Azure Monitor workspace"
  value       = azapi_resource.workspace.name
}

output "query_endpoint" {
  description = "The query endpoint for the Azure Monitor workspace"
  value       = "${azapi_resource.workspace.id}/metrics"
}

output "prometheus_query_endpoint" {
  description = "The Prometheus-compatible query endpoint"
  value       = azapi_resource.workspace.output.properties.metrics.prometheusQueryEndpoint
}

output "prometheus_remote_write_endpoint" {
  description = "The Prometheus remote-write base endpoint (without /api/v1/write)"
  value       = local.prometheus_remote_write_base
}

output "prometheus_metrics_ingest_endpoint" {
  description = "The metrics ingestion endpoint exposed by the default data collection endpoint"
  value       = local.metrics_ingest_endpoint
}

output "prometheus_data_collection_rule_id" {
  description = "The default data collection rule resource ID associated with the workspace"
  value       = azapi_resource.workspace.output.properties.defaultIngestionSettings.dataCollectionRuleResourceId
}

output "prometheus_data_collection_rule_immutable_id" {
  description = "Immutable ID (dcr-*) for the default data collection rule"
  value       = local.dcr_immutable_id
}

output "location" {
  description = "The location of the Azure Monitor workspace"
  value       = local.location_canonical
}

output "tags" {
  description = "The tags applied to the Azure Monitor workspace"
  value       = local.common_tags
}
