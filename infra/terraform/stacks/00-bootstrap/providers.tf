provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  storage_use_azuread = true
  subscription_id     = var.subscription_id
  tenant_id           = var.tenant_id
  use_oidc            = false # Set to true for GitHub Actions/federated identity
}

provider "azuread" {
  tenant_id = var.tenant_id
}

provider "azapi" {
}
