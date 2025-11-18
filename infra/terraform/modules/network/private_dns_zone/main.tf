locals {
  env_code        = lower(var.environment_code)
  workload_code   = lower(var.workload_name)
  identifier_code = var.identifier != "" ? lower(var.identifier) : ""
  region_code     = lower(var.region_code != null ? var.region_code : "")

  # CAF-style ordering: workload - env - region - role - optional identifier
  suffix_components = compact([local.workload_code, local.env_code, local.region_code, "dns", local.identifier_code == "" ? null : local.identifier_code])

  common_tags = merge({
    project     = local.workload_code
    environment = local.env_code
    role        = "network"
    managed_by  = "terraform"
  }, var.tags)
}

module "naming" {
  source        = "Azure/naming/azurerm"
  version       = "0.4.2"
  suffix        = local.suffix_components
  unique-length = 6
}

resource "azurerm_private_dns_zone" "private_dns_zone" {
  name                = var.name
  resource_group_name = var.resource_group_name
  tags                = local.common_tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "link" {
  name                  = var.link_name_override != "" ? var.link_name_override : "${module.naming.private_dns_zone.name}-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.private_dns_zone.name
  virtual_network_id    = var.virtual_networks_to_link_id

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}
