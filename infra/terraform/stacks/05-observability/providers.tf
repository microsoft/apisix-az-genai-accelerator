provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azapi" {
  # uses Azure CLI / environment authentication
}
