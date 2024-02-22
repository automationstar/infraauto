resource "azurerm_key_vault_access_policy" "example" {
  key_vault_id = azurerm_key_vault.example.id

  tenant_id = var.tenant_id
  object_id = var.service_principal_object_id

  key_permissions = [
    "get",
  ]

  secret_permissions = [
    "get",
  ]

  storage_permissions = [
    "get",
  ]
}
