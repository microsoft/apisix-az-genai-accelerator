module "regions" {
  source          = "Azure/avm-utl-regions/azurerm"
  version         = "0.5.0"
  use_cached_data = true
}

locals {
  region_object    = lookup(module.regions.regions_by_name_or_display_name, lower(var.location), null)
  _validate_region = local.region_object != null ? true : error("Invalid location '${var.location}'")

  location_canonical = local.region_object.name
  env_code           = lower(var.environment)
  workload_code      = lower(var.workload_name)
  identifier_code    = var.identifier != "" ? lower(var.identifier) : ""
  region             = local.region_object.geo_code

  # CAF-style ordering: workload - env - region - role - optional identifier
  suffix_components = compact([local.workload_code, local.env_code, local.region, "kv", local.identifier_code == "" ? null : local.identifier_code])

  common_tags = merge(var.tags, {
    project     = local.workload_code
    environment = local.env_code
    location    = local.region
    role        = "secrets"
    managed_by  = "terraform"
  })
}

module "naming" {
  source        = "Azure/naming/azurerm"
  version       = "0.4.2"
  suffix        = local.suffix_components
  unique-length = 6
}

# User-assigned managed identity for ACA access to Key Vault
resource "azurerm_user_assigned_identity" "aca_keyvault_identity" {
  name                = var.identity_name_override != "" ? var.identity_name_override : module.naming.user_assigned_identity.name_unique
  location            = local.location_canonical
  resource_group_name = var.resource_group_name
  tags                = local.common_tags
}

# Key Vault with configurable access
resource "azurerm_key_vault" "main" {
  name                = var.key_vault_name_override != "" ? var.key_vault_name_override : module.naming.key_vault.name_unique
  location            = local.location_canonical
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  sku_name            = "standard"

  # Security: Enable public access only when private endpoints are not used
  public_network_access_enabled = var.subnet_id == null

  # Use RBAC authorization for better security (instead of access policies)
  rbac_authorization_enabled = true

  # Enable purge protection for production safety
  purge_protection_enabled   = var.purge_protection_enabled
  soft_delete_retention_days = 7

  # Network ACLs - strict IP-based access only
  network_acls {
    bypass         = var.subnet_id == null ? "AzureServices" : "None"
    default_action = var.subnet_id == null ? (length(var.ip_rules) > 0 ? "Deny" : "Allow") : "Deny"
    ip_rules       = var.ip_rules
  }

  tags = local.common_tags
}

# RBAC role assignment for ACA managed identity (Key Vault Secrets User)
resource "azurerm_role_assignment" "aca_identity_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.aca_keyvault_identity.principal_id

  depends_on = [azurerm_key_vault.main]
}

# RBAC role assignment for deployment principal (Key Vault Secrets Officer)
resource "azurerm_role_assignment" "deployment_principal_secrets_officer" {
  count                = var.deployment_principal_id != null ? 1 : 0
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.deployment_principal_id

  depends_on = [azurerm_key_vault.main]
}

# Private endpoint for Key Vault (optional)
resource "azurerm_private_endpoint" "key_vault" {
  count               = var.subnet_id != null ? 1 : 0
  name                = module.naming.private_endpoint.name_unique
  location            = local.location_canonical
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = module.naming.private_service_connection.name_unique
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.private_dns_zone_id != null ? [1] : []
    content {
      name                 = module.naming.private_dns_zone_group.name_unique
      private_dns_zone_ids = [var.private_dns_zone_id]
    }
  }

  tags = local.common_tags
}
