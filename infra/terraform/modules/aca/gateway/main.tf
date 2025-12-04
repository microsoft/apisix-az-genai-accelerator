/// Module: aca/gateway
/// Purpose: Container App (init + main + optional sidecars), UA identity, env/secret parsing, registry auth
///

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
    azuread = { source = "hashicorp/azuread" }
    azapi   = { source = "azure/azapi" }
    time    = { source = "hashicorp/time" }
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
    role        = "gateway"
    managed_by  = "terraform"
  }, var.tags)

  app_insights_connection_string = azurerm_application_insights.this.connection_string
}

# ─────────────────────────────────────────────────────────────────────────────
# Naming
# ─────────────────────────────────────────────────────────────────────────────

module "naming" {
  source        = "Azure/naming/azurerm"
  version       = "0.4.2"
  # Role last: workload-env-region-role
  suffix        = compact([local.workload_code, local.env_code, local.region, "gateway", local.identifier_code == "" ? null : local.identifier_code])
  unique-length = 6
}

# ─────────────────────────────────────────────────────────────────────────────
# User-assigned identity for ACR pull
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_user_assigned_identity" "gateway" {
  name                = module.naming.user_assigned_identity.name_unique
  location            = local.location_canonical
  resource_group_name = var.rg_name
  tags                = local.common_tags
}

resource "azurerm_role_assignment" "gateway_acr_pull" {
  scope                = var.platform_acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.gateway.principal_id
}

# Azure Monitor Reader role assignment for Grafana managed identity authentication
resource "azurerm_role_assignment" "gateway_azure_monitor_reader" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.gateway.principal_id
}

# ─────────────────────────────────────────────────────────────────────────────
# Application Insights (optional)
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_application_insights" "this" {
  name                 = module.naming.application_insights.name_unique
  location             = local.location_canonical
  resource_group_name  = var.rg_name
  workspace_id         = var.log_analytics_workspace_id
  application_type     = "web"
  daily_data_cap_in_gb = var.app_insights_daily_cap_gb
  tags                 = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Environment variable processing (legacy .env file or Key Vault + app settings)
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # Key Vault mode - use only the secrets that actually exist
  kv_app_settings = var.app_settings
  kv_secret_names = var.secret_names

  # Use only the secrets that are provided, no hardcoded APISIX secrets
  all_kv_secrets = local.kv_secret_names

  # Direct environment variables
  direct_env_vars = var.direct_environment_variables

  # Final configuration combines non-secret app settings with direct env vars
  app_setting_env_vars = merge(local.kv_app_settings, local.direct_env_vars)

  container_identity_ids = toset([
    azurerm_user_assigned_identity.gateway.id,
    var.key_vault_managed_identity_id,
  ])

  # Azure Monitor configuration for OTel collector (always enabled)
  azure_monitor_config = {
    AZURE_MONITOR_WORKSPACE_ENDPOINT = var.azure_monitor_prometheus_endpoint
    AZURE_CLIENT_ID                  = azurerm_user_assigned_identity.gateway.client_id
  }

  # OpenTelemetry collector endpoint for APISIX plugin (always enabled)
  # In sidecar deployment, collector is accessible via localhost on standard HTTP port
  otel_collector_endpoint = "localhost:4318"
}

# ─────────────────────────────────────────────────────────────────────────────
# Container App
# ─────────────────────────────────────────────────────────────────────────────

resource "azurerm_container_app" "gateway" {
  name                         = module.naming.container_app.name_unique
  resource_group_name          = var.rg_name
  container_app_environment_id = var.aca_env_id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = tolist(local.container_identity_ids)
  }

  # ACR registry authentication using managed identity
  registry {
    server   = var.platform_acr_login
    identity = azurerm_user_assigned_identity.gateway.id
  }

  # Key Vault secret references
  dynamic "secret" {
    for_each = toset(local.all_kv_secrets)
    content {
      name                = secret.value
      key_vault_secret_id = "https://${var.key_vault_name}.vault.azure.net/secrets/${secret.value}"
      identity            = var.key_vault_managed_identity_id
    }
  }

  # Ingress configuration
  ingress {
    external_enabled = var.expose_gateway_public
    target_port      = var.gateway_target_port
    transport        = "auto"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  # Template configuration
  template {
    dynamic "volume" {
      for_each = var.gateway_e2e_test_mode ? ["apisix-conf"] : []
      content {
        name         = volume.value
        storage_type = "EmptyDir"
      }
    }
    # Init container for config rendering
    init_container {
      name   = "hydrenv-init"
      image  = var.hydrenv_image
      cpu    = 0.25
      memory = "0.5Gi"

      dynamic "env" {
        for_each = local.app_setting_env_vars
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.azure_monitor_config
        content {
          name  = env.key
          value = env.value
        }
      }

      env {
        name  = "OTEL_COLLECTOR_ENDPOINT"
        value = local.otel_collector_endpoint
      }

      dynamic "env" {
        for_each = toset(local.all_kv_secrets)
        content {
          name        = upper(replace(env.value, "-", "_"))
          secret_name = env.value
        }
      }

      dynamic "env" {
        for_each = local.app_insights_connection_string != "" ? [1] : []
        content {
          name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
          value = local.app_insights_connection_string
        }
      }

      volume_mounts {
        name = "shared-configs"
        path = "/shared-configs"
      }

      dynamic "volume_mounts" {
        for_each = var.gateway_e2e_test_mode ? [1] : []
        content {
          name = "apisix-conf"
          path = "/usr/local/apisix/conf"
        }
      }
    }

    # Main gateway container
    container {
      name   = "gateway"
      image  = var.gateway_image
      cpu    = var.gateway_cpu
      memory = var.gateway_memory

      volume_mounts {
        name = "shared-configs"
        path = "/shared-configs"
      }

      dynamic "volume_mounts" {
        for_each = var.gateway_e2e_test_mode ? [1] : []
        content {
          name = "apisix-conf"
          path = "/usr/local/apisix/conf"
        }
      }
    }

    # OpenTelemetry Collector sidecar
    container {
      name   = "otel-collector"
      image  = var.otel_collector_image
      cpu    = 0.25
      memory = "0.5Gi"

      # Use rendered config from shared volume
      args = ["--config=/shared-configs/otel-collector/config.yaml"]

      env {
        name  = "ENABLE_DEBUG_EXPORTER"
        value = "false"
      }

      volume_mounts {
        name = "shared-configs"
        path = "/shared-configs"
      }
    }

    dynamic "container" {
      for_each = var.gateway_e2e_test_mode && var.config_api_image != "" ? [1] : []
      content {
        name   = "gateway-config-api"
        image  = var.config_api_image
        cpu    = var.config_api_cpu
        memory = var.config_api_memory

        env {
          name  = "CONFIG_API_APISIX_CONF_PATH"
          value = "/usr/local/apisix/conf/apisix.yaml"
        }

        dynamic "env" {
          for_each = var.config_api_shared_secret != "" ? [1] : []
          content {
            name  = "CONFIG_API_SHARED_SECRET"
            value = var.config_api_shared_secret
          }
        }

        env {
          name  = "CONFIG_API_BIND_PORT"
          value = "9000"
        }

        volume_mounts {
          name = "apisix-conf"
          path = "/usr/local/apisix/conf"
        }
      }
    }

    # Volume for shared configs
    volume {
      name         = "shared-configs"
      storage_type = "EmptyDir"
    }

    # Scaling configuration
    min_replicas = var.gateway_min_replicas
    max_replicas = var.gateway_max_replicas
  }

  tags = local.common_tags
}
