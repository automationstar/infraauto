locals {
  hub_subscription_map = {
    eastus2_prod      = "59b2cd00-9406-4a41-a772-e073dbe19796"
    eastus2_nonprod   = "a5051462-84f2-4236-8e09-dc4b685e95af"
    centralus_prod    = "29ea5d6f-8539-4a95-8198-ca801994cbdb"
    centralus_nonprod = "32ca4feb-5c5d-4ac9-81d7-53e191bff3fd"
    westus3_prod      = "0b379ff1-4fa8-48c7-b2ed-c85c4d91c29f"
    westus3_nonprod   = "bed98fc6-17af-458b-a646-95defa044de4"
    eastus_prod       = "f57af375-a161-490e-956c-f75815022949"
    eastus_nonprod    = "30e06011-daaa-4a8a-ba09-e7af7c515231"
  }

  hub_vnet_map = {
    eastus2_prod      = "vnet-cvshub000"
    eastus2_nonprod   = "vnet-corp-hub-nonprod-use2"
    centralus_prod    = "vnet-cvshub001"
    centralus_nonprod = "vnet-corp-hub-nonprod-usc"
    westus3_prod      = "vnet-corp-hub-prod-usw3"
    westus3_nonprod   = "vnet-corp-hub-nonprod-usw3"
    eastus_prod       = "vnet-corp-hub-prod-use"
    eastus_nonprod    = "vnet-corp-hub-nonprod-use"
  }

  hub_vnet_rg_map = {
    eastus2_prod      = "rg-cvsntwkhub000"
    eastus2_nonprod   = "rg-corp-hub-nonprod-use2-ntwk"
    centralus_prod    = "rg-cvsntwkhub000"
    centralus_nonprod = "rg-corp-hub-nonprod-usc-ntwk"
    westus3_prod      = "rg-corp-hub-prod-usw3-ntwk"
    westus3_nonprod   = "rg-corp-hub-nonprod-usw3-ntwk"
    eastus_prod       = "rg-corp-hub-prod-use-ntwk"
    eastus_nonprod    = "rg-corp-hub-nonprod-use-ntwk"
  }

  hub_subscription_id = local.hub_subscription_map[local.region_environment]
  hub_vnet_name       = local.hub_vnet_map[local.region_environment]
  hub_vnet_rg         = local.hub_vnet_rg_map[local.region_environment]
  hub_vnet_id         = "/subscriptions/${local.hub_subscription_id}/resourceGroups/${local.hub_vnet_rg}/providers/Microsoft.Network/virtualNetworks/${local.hub_vnet_name}"

}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  count                     = var.is_peered && !local.is_client ? 1 : 0
  name                      = "peer-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-spk"
  resource_group_name       = azurerm_resource_group.network_rg[0].name
  virtual_network_name      = azurerm_virtual_network.vnet[0].name
  remote_virtual_network_id = local.hub_vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = true

  lifecycle {
    replace_triggered_by = [azurerm_virtual_network.vnet[0].address_space]
  }
}
resource "random_string" "peering" {
  length  = 6
  special = false
  upper   = false
}


resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  count                     = var.is_peered && !local.is_client && !contains(["eastus2_prod", "centralus_prod"], local.region_environment) ? 1 : 0
  provider                  = azurerm.hub
  name                      = "peer-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}${random_string.peering.result}-hub"
  resource_group_name       = local.hub_vnet_rg
  virtual_network_name      = local.hub_vnet_name
  remote_virtual_network_id = azurerm_virtual_network.vnet[0].id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false

  lifecycle {
    replace_triggered_by = [azurerm_virtual_network.vnet[0].address_space]
    ignore_changes = [
      name
    ]

    precondition {
      condition     = contains(["eastus2_nonprod","centralus_nonprod"], local.region_environment) ? var.container_index >= 2 : true
      error_message   = "This spoke is attempting to peer to either the Non-Prod EastUS2 or CentralUS hub, but is set to use legacy non-production address space. Set container_index = 2 or container_index = 3 to use 10.229.xx.xx address space, or or change region_environment in provider.tf to a Production hub; e.g. eastus2_prod."
    }
  }

}

resource "azurerm_virtual_network_peering" "hub_eastus2_to_spoke" {
  count                     = var.is_peered && local.region_environment == "eastus2_prod" && !local.is_client ? 1 : 0
  provider                  = azurerm.hub_eastus2
  name                      = "peer-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}${random_string.peering.result}-hub"
  resource_group_name       = local.hub_vnet_rg
  virtual_network_name      = local.hub_vnet_name
  remote_virtual_network_id = azurerm_virtual_network.vnet[0].id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false

  lifecycle {
    replace_triggered_by = [azurerm_virtual_network.vnet[0].address_space]
    ignore_changes = [
      name
    ]
    precondition {
      condition     = var.container_index < 2
      error_message   = "This spoke is attempting to peer to the Production EastUS2 hub but is set to use non-production address space. Set container_index = 0 for 10.83.xx.xx or container_index = 1 for 10.85.xx.xx, or change region_environment in provider.tf to a non-production hub; e.g. eastus2_nonprod."
    }
  }
}

resource "azurerm_virtual_network_peering" "hub_centralus_to_spoke" {
  count                     = var.is_peered && local.region_environment == "centralus_prod" && !local.is_client ? 1 : 0
  provider                  = azurerm.hub_centralus
  name                      = "peer-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}${random_string.peering.result}-hub"
  resource_group_name       = local.hub_vnet_rg
  virtual_network_name      = local.hub_vnet_name
  remote_virtual_network_id = azurerm_virtual_network.vnet[0].id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = true
  use_remote_gateways          = false

  lifecycle {
    replace_triggered_by = [azurerm_virtual_network.vnet[0].address_space]
    ignore_changes = [
      name
    ]
    precondition {
      condition     = var.container_index < 2
      error_message   = "This spoke is attempting to peer to the Production CentralUS hub, but is set to use non-production address space. Set container_index = 0 for 10.83.xx.xx or container_index = 1 or 10.85.xx.xx, or change region_environment in provider.tf to a non-production hub; e.g. centralus_nonprod."
    }
  
  }
}