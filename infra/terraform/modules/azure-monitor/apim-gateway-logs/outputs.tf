/// Outputs for APIM-style gateway log ingestion

output "dce_id" {
  description = "Data Collection Endpoint resource ID"
  value       = azurerm_monitor_data_collection_endpoint.this.id
}

output "dcr_id" {
  description = "Data Collection Rule resource ID"
  value       = azurerm_monitor_data_collection_rule.this.id
}

output "dcr_immutable_id" {
  description = "Immutable ID of the DCR (dcr-*)"
  value       = azurerm_monitor_data_collection_rule.this.immutable_id
}

output "ingest_uri" {
  description = "Prebuilt ingestion URI for the configured stream"
  value       = local.ingest_uri
}

output "stream_name" {
  description = "Log stream name used for ingestion"
  value       = var.stream_name
}
