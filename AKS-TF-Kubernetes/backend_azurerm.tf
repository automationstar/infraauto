terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.56" # Example version, adjust as needed
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 1.5" # Example version, adjust as needed
    }
  }
}
