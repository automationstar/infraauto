terraform {
  required_version = ">= 0.13" # Ensure you are using a Terraform version that supports the latest provider syntax

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0" # Update to a more recent version
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0" # Update to a more recent version
    }
  }
}

provider "azuread" {
  # Note: `subscription_id` is not a valid configuration for the `azuread` provider.
}

provider "azurerm" {
  features {} # The features block is still required, but should be empty
}
