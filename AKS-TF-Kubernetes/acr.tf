resource "azurerm_container_registry" "acr" {
  name                = format("%sacr", var.short_prefix)
  resource_group_name = azurerm_resource_group.rg_aks.name
  location            = azurerm_resource_group.rg_aks.location
  sku                 = "Premium"
  admin_enabled       = true

  tags = {
    Environment = var.environment
  }
}
