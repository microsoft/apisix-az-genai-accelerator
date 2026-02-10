/// Stack: 20-workload
/// Purpose: Container Apps environment and gateway deployment leveraging foundation outputs

module "regions" {
  source          = "Azure/avm-utl-regions/azurerm"
  version         = "0.5.0"
  use_cached_data = true
}

locals {
  region_object    = lookup(module.regions.regions_by_name_or_display_name, lower(var.location), null)
  _validate_region = local.region_object != null ? true : error("Invalid location '${var.location}'")

  location_canonical = local.region_object.name
  region_code        = local.region_object.geo_code
  env_code           = lower(var.environment_code)
  workload_code      = lower(var.workload_name)
  identifier_code    = var.identifier != "" ? lower(var.identifier) : ""

  common_tags = merge({
    project     = local.workload_code
    environment = local.env_code
    location    = local.region_code
    managed_by  = "terraform"
  }, var.tags)

  sim_ptu1_name  = lower(join("-", compact([var.workload_name, "sim", "ptu1", var.environment_code, local.region_code, var.identifier == "" ? null : var.identifier])))
  sim_payg1_name = lower(join("-", compact([var.workload_name, "sim", "payg1", var.environment_code, local.region_code, var.identifier == "" ? null : var.identifier])))
  sim_payg2_name = lower(join("-", compact([var.workload_name, "sim", "payg2", var.environment_code, local.region_code, var.identifier == "" ? null : var.identifier])))

  openai_outputs = var.use_provisioned_azure_openai ? data.terraform_remote_state.openai[0].outputs : null

  provisioned_backends = local.openai_outputs != null && can(local.openai_outputs.azure_openai_endpoints) ? local.openai_outputs.azure_openai_endpoints : []

  provisioned_backend_env_vars = {
    for idx, backend in local.provisioned_backends :
    "AZURE_OPENAI_ENDPOINT_${idx}" => backend.endpoint
  }

  provisioned_backend_priorities = {
    for idx, backend in local.provisioned_backends :
    "AZURE_OPENAI_PRIORITY_${idx}" => tostring(backend.priority)
  }

  provisioned_backend_weights = {
    for idx, backend in local.provisioned_backends :
    "AZURE_OPENAI_WEIGHT_${idx}" => tostring(backend.weight)
  }

  provisioned_backend_resource_ids = local.openai_outputs != null && can(local.openai_outputs.azure_openai_resource_ids) ? local.openai_outputs.azure_openai_resource_ids : []

  provisioned_secret_names = local.openai_outputs != null && can(local.openai_outputs.azure_openai_key_vault_secret_names) ? local.openai_outputs.azure_openai_key_vault_secret_names : []

  derived_secret_keys = distinct(keys(var.secrets))

  derived_app_settings = var.app_settings

  derived_secret_names = [
    for key in local.derived_secret_keys : lower(replace(key, "_", "-"))
  ]


  simulator_env = var.gateway_e2e_test_mode && var.simulator_image != "" ? {
    AZURE_OPENAI_ENDPOINT_0 = "https://${local.sim_ptu1_name}.${module.env.default_domain}"
    AZURE_OPENAI_ENDPOINT_1 = "https://${local.sim_payg1_name}.${module.env.default_domain}"
    AZURE_OPENAI_ENDPOINT_2 = "https://${local.sim_payg2_name}.${module.env.default_domain}"
    AZURE_OPENAI_KEY_0      = var.simulator_api_key
    AZURE_OPENAI_KEY_1      = var.simulator_api_key
    AZURE_OPENAI_KEY_2      = var.simulator_api_key
    AZURE_OPENAI_NAME_0     = "ptu-backend-1"
    AZURE_OPENAI_NAME_1     = "payg-backend-1"
    AZURE_OPENAI_NAME_2     = "payg-backend-2"
    AZURE_OPENAI_PRIORITY_0 = "10"
    AZURE_OPENAI_PRIORITY_1 = "5"
    AZURE_OPENAI_PRIORITY_2 = "1"
    AZURE_OPENAI_WEIGHT_0   = "1"
    AZURE_OPENAI_WEIGHT_1   = "1"
    AZURE_OPENAI_WEIGHT_2   = "1"
  } : {}

  final_app_settings = merge(
    local.simulator_env,
    local.provisioned_backend_env_vars,
    local.provisioned_backend_priorities,
    local.provisioned_backend_weights,
    local.derived_app_settings
  )

  final_secret_names = distinct(concat(
    local.provisioned_secret_names,
    local.derived_secret_names
  ))

}

# ─────────────────────────────────────────────────────────────────────────────
# Data sources
# ─────────────────────────────────────────────────────────────────────────────

data "azurerm_client_config" "current" {}

data "terraform_remote_state" "foundation" {
  backend = "azurerm"
  config = {
    use_azuread_auth     = true
    tenant_id            = var.tenant_id
    resource_group_name  = var.state_resource_group_name
    storage_account_name = var.state_storage_account_name
    container_name       = var.state_container_name
    key                  = var.foundation_state_blob_key
  }
}

data "terraform_remote_state" "openai" {
  count   = var.use_provisioned_azure_openai ? 1 : 0
  backend = "azurerm"
  config = {
    use_azuread_auth     = true
    tenant_id            = var.tenant_id
    resource_group_name  = var.state_resource_group_name
    storage_account_name = var.state_storage_account_name
    container_name       = var.state_container_name
    key                  = var.openai_state_blob_key
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# ACA Environment
# ─────────────────────────────────────────────────────────────────────────────

module "env" {
  source = "../../modules/aca/environment"

  environment_code           = var.environment_code
  location                   = var.location
  workload_name              = var.workload_name
  identifier                 = var.identifier
  rg_name_override           = var.workload_rg_name_override
  aca_env_name_override      = var.aca_env_name_override
  log_analytics_workspace_id = var.log_analytics_workspace_id
  log_retention_days         = var.log_retention_days

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Azure Monitor Workspace
# ─────────────────────────────────────────────────────────────────────────────

module "azure_monitor_workspace" {
  count  = var.azure_monitor_workspace_id == "" ? 1 : 0
  source = "../../modules/azure-monitor/workspace"

  subscription_id  = data.azurerm_client_config.current.subscription_id
  rg_name          = module.env.rg_name
  location         = var.location
  environment_code = var.environment_code
  workload_name    = var.workload_name
  identifier       = var.identifier
  tags             = local.common_tags
}

locals {
  azure_monitor_workspace_id              = var.azure_monitor_workspace_id != "" ? var.azure_monitor_workspace_id : module.azure_monitor_workspace[0].workspace_id
  azure_monitor_prometheus_endpoint       = var.azure_monitor_prometheus_endpoint != "" ? var.azure_monitor_prometheus_endpoint : module.azure_monitor_workspace[0].prometheus_remote_write_endpoint
  azure_monitor_prometheus_query_endpoint = var.azure_monitor_prometheus_query_endpoint != "" ? var.azure_monitor_prometheus_query_endpoint : module.azure_monitor_workspace[0].prometheus_query_endpoint
  azure_monitor_prometheus_dcr_id         = var.azure_monitor_prometheus_dcr_id != "" ? var.azure_monitor_prometheus_dcr_id : module.azure_monitor_workspace[0].prometheus_data_collection_rule_id
}

# ─────────────────────────────────────────────────────────────────────────────
# APIM-style Gateway Logs (DCE + DCR for logs ingestion)
# ─────────────────────────────────────────────────────────────────────────────

# Role assignment to grant gateway identity monitoring reader access
resource "azurerm_role_assignment" "gateway_monitoring_reader" {
  scope                = local.azure_monitor_workspace_id
  role_definition_name = "Monitoring Reader"
  principal_id         = module.gateway.gateway_identity_principal_id
}

resource "azurerm_role_assignment" "gateway_prometheus_publisher" {
  count                = var.azure_monitor_prometheus_dcr_id == "" ? 0 : 1
  scope                = var.azure_monitor_prometheus_dcr_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = module.gateway.gateway_identity_principal_id
}

# Grant workspace-level permission for DCR log ingestion
resource "azurerm_role_assignment" "gateway_logs_ingest" {
  scope                = module.env.law_id
  role_definition_name = "Log Analytics Contributor"
  principal_id         = module.gateway.gateway_identity_principal_id
}

# Grant gateway identity permission to publish via the DCR/DCE ingestion pipeline
resource "azurerm_role_assignment" "gateway_logs_metrics_publisher" {
  count                = var.gateway_log_ingest_dcr_id != "" ? 1 : 0
  scope                = var.gateway_log_ingest_dcr_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = module.gateway.gateway_identity_principal_id
}

# Allow gateway identity to publish to the DCE endpoint directly
resource "azurerm_role_assignment" "gateway_logs_dce_metrics_publisher" {
  count                = var.gateway_log_ingest_dce_id != "" ? 1 : 0
  scope                = var.gateway_log_ingest_dce_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = module.gateway.gateway_identity_principal_id
}

# ─────────────────────────────────────────────────────────────────────────────
# Azure AI Foundry / OpenAI (Entra ID data-plane access)
# ─────────────────────────────────────────────────────────────────────────────
#
# When backends require Entra ID auth, the gateway identity must be granted the
# Cognitive Services OpenAI User role on each Foundry/OpenAI account.
#
resource "azurerm_role_assignment" "gateway_openai_user" {
  for_each = {
    for idx, rid in local.provisioned_backend_resource_ids : tostring(idx) => rid
  }

  scope                = each.value
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = module.gateway.gateway_identity_principal_id
}

# Broader DCR permissions for log ingestion (covers data collection rule operations)
resource "azurerm_role_assignment" "gateway_logs_dcr_contributor" {
  count                = var.gateway_log_ingest_dcr_id != "" ? 1 : 0
  scope                = var.gateway_log_ingest_dcr_id
  role_definition_name = "Monitoring Contributor"
  principal_id         = module.gateway.gateway_identity_principal_id
}

# ─────────────────────────────────────────────────────────────────────────────
# Reference platform ACR (required)
# ─────────────────────────────────────────────────────────────────────────────

data "azurerm_container_registry" "platform" {
  name                = var.platform_acr_name
  resource_group_name = var.platform_resource_group_name
}

# ─────────────────────────────────────────────────────────────────────────────
# Gateway Container App
# ─────────────────────────────────────────────────────────────────────────────

module "gateway" {
  source = "../../modules/aca/gateway"

  rg_name          = module.env.rg_name
  aca_env_id       = module.env.aca_env_id
  environment_code = var.environment_code
  location         = var.location
  subscription_id  = data.azurerm_client_config.current.subscription_id
  workload_name    = var.workload_name
  identifier       = var.identifier

  # ACR configuration
  platform_acr_id    = data.azurerm_container_registry.platform.id
  platform_acr_login = data.azurerm_container_registry.platform.login_server

  # Container images
  gateway_image            = var.gateway_image
  hydrenv_image            = var.hydrenv_image
  gateway_e2e_test_mode    = var.gateway_e2e_test_mode
  config_api_image         = var.config_api_image
  config_api_shared_secret = var.config_api_shared_secret

  # Key Vault configuration
  key_vault_name                = var.key_vault_name
  key_vault_managed_identity_id = var.aca_managed_identity_id
  app_settings                  = local.final_app_settings
  secret_names                  = local.final_secret_names

  # Gateway configuration
  expose_gateway_public       = var.expose_gateway_public
  gateway_target_port         = var.gateway_target_port
  gateway_cpu                 = var.gateway_cpu
  gateway_memory              = var.gateway_memory
  gateway_http_concurrency    = var.gateway_http_concurrency
  gateway_cpu_scale_threshold = var.gateway_cpu_scale_threshold
  gateway_min_replicas        = var.gateway_min_replicas
  gateway_max_replicas        = var.gateway_max_replicas

  # Observability
  log_analytics_workspace_id        = module.env.law_id
  app_insights_daily_cap_gb         = var.app_insights_daily_cap_gb
  app_insights_connection_string    = var.app_insights_connection_string
  azure_monitor_workspace_id        = local.azure_monitor_workspace_id
  azure_monitor_prometheus_endpoint = local.azure_monitor_prometheus_endpoint
  tenant_id                         = data.azurerm_client_config.current.tenant_id

  # Observability sidecars
  otel_collector_image  = var.otel_collector_image
  otel_collector_cpu    = var.otel_collector_cpu
  otel_collector_memory = var.otel_collector_memory

  tags = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Simulators (test mode only)
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_container_app" "sim_payg1" {
  count                        = var.gateway_e2e_test_mode && var.simulator_image != "" ? 1 : 0
  name                         = local.sim_payg1_name
  resource_group_name          = module.env.rg_name
  container_app_environment_id = module.env.aca_env_id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [module.gateway.gateway_identity_id]
  }

  registry {
    server   = data.azurerm_container_registry.platform.login_server
    identity = module.gateway.gateway_identity_id
  }

  secret {
    name  = "simulator-deployment-config"
    value = file("${path.module}/../../../../apim-genai-gateway-toolkit/infra/simulators/simulator_file_content/simulator_deployment_config.json")
  }

  ingress {
    external_enabled = true
    target_port      = var.simulator_port
    transport        = "auto"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    container {
      name   = "simulator"
      image  = var.simulator_image
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "SIMULATOR_MODE"
        value = "generate"
      }

      env {
        name  = "SIMULATOR_API_KEY"
        value = var.simulator_api_key
      }

      env {
        name  = "AZURE_OPENAI_DEPLOYMENT"
        value = "gpt-35-turbo"
      }

      env {
        name  = "AZURE_OPENAI_EMBEDDING_DEPLOYMENT"
        value = "text-embedding-3-small"
      }

      env {
        name  = "PORT"
        value = tostring(var.simulator_port)
      }

      env {
        name  = "OPENAI_DEPLOYMENT_CONFIG_PATH"
        value = "/mnt/deployment-config/simulator-deployment-config"
      }

      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = module.gateway.app_insights_connection_string
      }

      volume_mounts {
        name = "deployment-config"
        path = "/mnt/deployment-config"
      }
    }

    min_replicas = 1
    max_replicas = 1

    volume {
      name         = "deployment-config"
      storage_type = "Secret"
    }
  }

  tags = merge(local.common_tags, { role = "simulator" })
}

resource "azurerm_container_app" "sim_ptu1" {
  count                        = var.gateway_e2e_test_mode && var.simulator_image != "" ? 1 : 0
  name                         = local.sim_ptu1_name
  resource_group_name          = module.env.rg_name
  container_app_environment_id = module.env.aca_env_id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [module.gateway.gateway_identity_id]
  }

  registry {
    server   = data.azurerm_container_registry.platform.login_server
    identity = module.gateway.gateway_identity_id
  }

  secret {
    name  = "simulator-deployment-config"
    value = file("${path.module}/../../../../apim-genai-gateway-toolkit/infra/simulators/simulator_file_content/simulator_deployment_config.json")
  }

  ingress {
    external_enabled = true
    target_port      = var.simulator_port
    transport        = "auto"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    container {
      name   = "simulator"
      image  = var.simulator_image
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "SIMULATOR_MODE"
        value = "generate"
      }

      env {
        name  = "SIMULATOR_API_KEY"
        value = var.simulator_api_key
      }

      env {
        name  = "AZURE_OPENAI_DEPLOYMENT"
        value = "gpt-35-turbo"
      }

      env {
        name  = "AZURE_OPENAI_EMBEDDING_DEPLOYMENT"
        value = "text-embedding-3-small"
      }

      env {
        name  = "PORT"
        value = tostring(var.simulator_port)
      }

      env {
        name  = "OPENAI_DEPLOYMENT_CONFIG_PATH"
        value = "/mnt/deployment-config/simulator-deployment-config"
      }

      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = module.gateway.app_insights_connection_string
      }

      volume_mounts {
        name = "deployment-config"
        path = "/mnt/deployment-config"
      }
    }

    min_replicas = 1
    max_replicas = 1

    volume {
      name         = "deployment-config"
      storage_type = "Secret"
    }
  }

  tags = merge(local.common_tags, { role = "simulator" })
}

resource "azurerm_container_app" "sim_payg2" {
  count                        = var.gateway_e2e_test_mode && var.simulator_image != "" ? 1 : 0
  name                         = local.sim_payg2_name
  resource_group_name          = module.env.rg_name
  container_app_environment_id = module.env.aca_env_id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [module.gateway.gateway_identity_id]
  }

  registry {
    server   = data.azurerm_container_registry.platform.login_server
    identity = module.gateway.gateway_identity_id
  }

  secret {
    name  = "simulator-deployment-config"
    value = file("${path.module}/../../../../apim-genai-gateway-toolkit/infra/simulators/simulator_file_content/simulator_deployment_config.json")
  }

  ingress {
    external_enabled = true
    target_port      = var.simulator_port
    transport        = "auto"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    container {
      name   = "simulator"
      image  = var.simulator_image
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "SIMULATOR_MODE"
        value = "generate"
      }

      env {
        name  = "SIMULATOR_API_KEY"
        value = var.simulator_api_key
      }

      env {
        name  = "AZURE_OPENAI_DEPLOYMENT"
        value = "gpt-35-turbo"
      }

      env {
        name  = "AZURE_OPENAI_EMBEDDING_DEPLOYMENT"
        value = "text-embedding-3-small"
      }

      env {
        name  = "PORT"
        value = tostring(var.simulator_port)
      }

      env {
        name  = "OPENAI_DEPLOYMENT_CONFIG_PATH"
        value = "/mnt/deployment-config/simulator-deployment-config"
      }

      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = module.gateway.app_insights_connection_string
      }

      volume_mounts {
        name = "deployment-config"
        path = "/mnt/deployment-config"
      }
    }

    min_replicas = 1
    max_replicas = 1

    volume {
      name         = "deployment-config"
      storage_type = "Secret"
    }
  }

  tags = merge(local.common_tags, { role = "simulator" })
}

# ─────────────────────────────────────────────────────────────────────────────
# Alerts (optional)
# ─────────────────────────────────────────────────────────────────────────────

module "alerts" {
  count  = var.enable_alerts ? 1 : 0
  source = "../../modules/aca/alerts"

  enable_alerts                  = var.enable_alerts
  environment_code               = var.environment_code
  workload_name                  = var.workload_name
  identifier                     = var.identifier
  law_id                         = module.env.law_id
  gateway_app_name               = module.gateway.gateway_app_name
  rg_name                        = module.env.rg_name
  location                       = var.location
  alert_email_receivers          = var.alert_email_receivers
  alert_webhook_receivers        = var.alert_webhook_receivers
  alert_5xx_threshold_percent    = var.alert_5xx_threshold_percent
  alert_429_threshold_percent    = var.alert_429_threshold_percent
  alert_latency_p95_threshold_ms = var.alert_latency_p95_threshold_ms

  tags = local.common_tags
}
