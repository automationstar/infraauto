resource "azurerm_resource_group" "rg_aks" {
  name     = format("%s-aks", var.prefix)
  location = var.location

  tags = {
    Environment = var.environment
  }
}
