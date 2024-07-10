data "azurerm_resources" "external_vnet" {
  count = var.peer_external_vnet.name != null && !local.is_client ? 1 : 0

  name                = var.peer_external_vnet.name
  resource_group_name = var.peer_external_vnet.resource_group
}

resource "azurerm_virtual_network_peering" "spoke_to_external" {
  count = var.peer_external_vnet.name != null && !local.is_client ? 1 : 0

  name                      = "peer-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-spkexternal"
  resource_group_name       = azurerm_resource_group.network_rg[0].name
  virtual_network_name      = azurerm_virtual_network.vnet[0].name
  remote_virtual_network_id = data.azurerm_resources.external_vnet[0].resources[0].id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false

  lifecycle {
    replace_triggered_by = [azurerm_virtual_network.vnet[0].address_space]
  }
}

resource "azurerm_virtual_network_peering" "external_to_spoke" {
  count = var.peer_external_vnet.name != null && !local.is_client ? 1 : 0

  name                      = "peer-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-externalspk"
  resource_group_name       = var.peer_external_vnet.resource_group
  virtual_network_name      = var.peer_external_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.vnet[0].id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false

  lifecycle {
    replace_triggered_by = [azurerm_virtual_network.vnet[0].address_space]
  }
}