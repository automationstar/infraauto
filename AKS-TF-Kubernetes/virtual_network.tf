resource "azurerm_virtual_network" "vnet_aks" {
  name                = format("%s-vnet", var.prefix)
  location            = azurerm_resource_group.rg_aks.location
  resource_group_name = azurerm_resource_group.rg_aks.name
  address_space       = [var.vnet_cidr]
}

resource "azurerm_subnet" "subnet_aks" {
  name                 = "containers"
  resource_group_name  = azurerm_resource_group.rg_aks.name
  virtual_network_name = azurerm_virtual_network.vnet_aks.name
  address_prefixes     = [var.subnet_cidr]
  service_endpoints    = ["Microsoft.Sql"]

  # If you're using delegation or special subnet settings, ensure those are included here.
}
