terraform {
  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = "3.87.0"
      configuration_aliases = [azurerm.hub_eastus2, azurerm.hub_centralus, azurerm.hub]
    }
    infoblox = {
      source  = "infobloxopen/infoblox"
      version = "2.4.1"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "1.11.0"
    }
  }
}

provider "azapi" {
  alias           = "azapi"
  tenant_id       = data.azurerm_client_config.current.tenant_id
  subscription_id = data.azurerm_subscription.current.id
  use_oidc        = true
}
