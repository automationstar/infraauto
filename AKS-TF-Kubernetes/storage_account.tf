resource "azurerm_storage_account" "sa_vault" {
  name                     = "${var.short_prefix}vault"
  location                 = azurerm_resource_group.rg_aks.location
  resource_group_name      = azurerm_resource_group.rg_aks.name
  account_tier             = "Standard"
  account_kind             = "StorageV2"
  account_replication_type = "LRS"
  access_tier              = "Hot"
  enable_https_traffic_only = true

  # Note: Blob and file encryption are enabled by default in Azure, and the settings are managed directly in the Azure portal.
}

resource "azurerm_storage_container" "sc_vault" {
  name                  = "vault"
  storage_account_name  = azurerm_storage_account.sa_vault.name
  container_access_type = "private"
}

# Repeat for `sa_velero` and `sc_velero` with appropriate names and settings
