terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.27" # Compatible with enterprise pattern (~> 3.1 updated to latest)
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.3"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.0" # Matches enterprise pattern (~> 1.0 updated)
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.10"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}
