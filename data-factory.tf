locals {
  adf_subnet_name_list = [for subnet in local.all_subnets : subnet.name if subnet.name == var.data_factory.subnet_name]
  adf_subnet_name      = length(local.adf_subnet_name_list) != 0 ? local.adf_subnet_name_list[0] : var.data_factory.external_subnet_id != null ? var.data_factory.external_subnet_id : null
}
resource "azurerm_data_factory" "adf" {
  count               = local.adf_subnet_name != null ? 1 : 0
  name                = "${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-adf"
  location            = var.location
  resource_group_name = var.data_factory.ud_resource_group != null ? azurerm_resource_group.ud_rgs["${var.data_factory.ud_resource_group}"].name : azurerm_resource_group.adf_rg[0].name

  public_network_enabled          = false
  managed_virtual_network_enabled = var.data_factory.legacy_adf == true ? false : true


  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags,
      global_parameter
    ]
  }
  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.base_kv_uai[0].id]
  }

  customer_managed_key_id          = local.base_key_id
  customer_managed_key_identity_id = azurerm_user_assigned_identity.base_kv_uai[0].id

}

#### ADF Backwards Compatibility Resources

resource "azurerm_data_factory_integration_runtime_self_hosted" "adf_int_shr" {
  count           = local.adf_subnet_name != null && var.data_factory.legacy_adf == true ? 1 : 0
  name            = "dfshir-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}"
  data_factory_id = azurerm_data_factory.adf[0].id
}

resource "azurerm_data_factory_linked_service_azure_blob_storage" "adf_lsabs" {
  count             = local.adf_subnet_name != null && var.data_factory.legacy_adf == true ? 1 : 0
  name              = "adflsabs-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}"
  data_factory_id   = azurerm_data_factory.adf[0].id
  connection_string = azurerm_storage_account.adf_st[0].primary_connection_string
}

resource "azurerm_data_factory_integration_runtime_azure_ssis" "adf_ssis" {
  count           = local.adf_subnet_name != null && var.data_factory.legacy_adf == true ? 1 : 0
  name            = "dfazssisir-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}"
  data_factory_id = azurerm_data_factory.adf[0].id
  location        = var.location

  node_size = "Standard_D8_v3"
  proxy {
    self_hosted_integration_runtime_name = azurerm_data_factory_integration_runtime_self_hosted.adf_int_shr[0].name
    staging_storage_linked_service_name  = azurerm_data_factory_linked_service_azure_blob_storage.adf_lsabs[0].name
  }
}

#### ADF Backwards Compatibility Resources

resource "azurerm_key_vault" "adf_keyvault" {
  depends_on = [local.peering_resources]

  count = local.adf_subnet_name != null && var.data_factory.legacy_adf != true ? 1 : 0

  name                          = var.random_kv_names ? "kv-${var.application_id}${random_string.kvname.result}adf" : "kv-${var.line_of_business}${var.application_id}${local.env_region}adf"
  location                      = var.location
  resource_group_name           = var.data_factory.ud_resource_group != null ? azurerm_resource_group.ud_rgs["${var.data_factory.ud_resource_group}"].name : azurerm_resource_group.adf_rg[0].name
  enabled_for_disk_encryption   = true
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days    = 7
  purge_protection_enabled      = true
  enable_rbac_authorization     = true
  public_network_access_enabled = var.public_keyvaults
  sku_name                      = "premium"
  network_acls {
    default_action = var.public_keyvaults ? "Allow" : "Deny"
    bypass         = "AzureServices"
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags,
      enabled_for_template_deployment
    ]
  }
}

resource "azurerm_private_endpoint" "adf_keyvault_pep" {
  count = local.adf_subnet_name != null && var.public_keyvaults == false && var.data_factory.legacy_adf != true ? 1 : 0

  name                = "pep-${var.line_of_business}${var.application_id}${local.env_region}adf-kv"
  location            = var.location
  resource_group_name = var.data_factory.ud_resource_group != null ? azurerm_resource_group.ud_rgs["${var.data_factory.ud_resource_group}"].name : azurerm_resource_group.adf_rg[0].name
  subnet_id           = azurerm_subnet.subnets[local.adf_subnet_name].id

  private_service_connection {
    name                           = "adf-de-kv-privateserviceconnection"
    private_connection_resource_id = azurerm_key_vault.adf_keyvault[0].id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.vaultcore.azure.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }
}

resource "azurerm_data_factory_managed_private_endpoint" "managed_pe" {
  count              = local.adf_subnet_name != null && var.public_keyvaults == false && var.data_factory.legacy_adf != true ? 1 : 0
  name               = "${azurerm_storage_account.adf_st[0].name}-${azurerm_data_factory.adf[0].name}-blob"
  data_factory_id    = azurerm_data_factory.adf[0].id
  target_resource_id = azurerm_storage_account.adf_st[0].id
  subresource_name   = "blob"
}

resource "time_sleep" "adf_kv_dns_propagation" {
  depends_on      = [azurerm_private_endpoint.adf_keyvault_pep]
  count           = var.public_keyvaults != true && local.adf_subnet_name != null && var.data_factory.legacy_adf != true ? 1 : 0
  create_duration = "3m"
}

resource "azurerm_role_assignment" "adf_kv_key_access_admin_role" {
  count                = local.adf_subnet_name != null && var.data_factory.legacy_adf != true ? 1 : 0
  scope                = azurerm_key_vault.adf_keyvault[0].id
  role_definition_name = "Key Vault Administrator"
  principal_id         = azurerm_user_assigned_identity.base_kv_uai[0].principal_id
}

resource "azurerm_role_assignment" "adf_kv_key_access_admin_role_system_id" {
  count                = local.adf_subnet_name != null && var.data_factory.legacy_adf != true ? 1 : 0
  scope                = azurerm_key_vault.adf_keyvault[0].id
  role_definition_name = "Key Vault Administrator"
  principal_id         = azurerm_data_factory.adf[0].identity.0.principal_id
}

resource "azurerm_data_factory_linked_service_key_vault" "adf_kv" {
  count           = local.adf_subnet_name != null && var.data_factory.legacy_adf != true ? 1 : 0
  name            = var.random_kv_names ? "kv-${var.application_id}${random_string.kvname.result}adf" : "kv-${var.line_of_business}${var.application_id}${local.env_region}adf"
  data_factory_id = azurerm_data_factory.adf[0].id
  key_vault_id    = azurerm_key_vault.adf_keyvault[0].id
}

resource "azurerm_data_factory_integration_runtime_azure" "adf_runtime" {
  count                   = local.adf_subnet_name != null && var.data_factory.legacy_adf != true ? 1 : 0
  name                    = "integration-runtime-azure-managed-vnet"
  data_factory_id         = azurerm_data_factory.adf[0].id
  location                = var.location
  virtual_network_enabled = true
}

resource "null_resource" "adf_credentials" {
  count = local.adf_subnet_name != null && var.data_factory.legacy_adf != true ? 1 : 0
  provisioner "local-exec" {
    working_dir = local.script_dir
    command     = "chmod +x datafactory_credentials.sh && ./datafactory_credentials.sh  ${azurerm_data_factory.adf[0].name} ${azurerm_data_factory.adf[0].resource_group_name} ${azurerm_user_assigned_identity.base_kv_uai[0].id} UserManagedIdentityCredentials $SUBSCRIPTION_ID"

    environment = {
      SUBSCRIPTION_ID = split("/", data.azurerm_subscription.current.id)[2]
    }
  }
}

resource "null_resource" "adf_linked_service_blob" {
  depends_on = [null_resource.adf_credentials]
  count      = local.adf_subnet_name != null && var.data_factory.legacy_adf != true ? 1 : 0
  provisioner "local-exec" {
    working_dir = local.script_dir
    command     = "chmod +x datafactory_linkedservice.sh && ./datafactory_linkedservice.sh  ${azurerm_data_factory.adf[0].name} ${azurerm_data_factory.adf[0].resource_group_name} ${azurerm_user_assigned_identity.base_kv_uai[0].id} UserManagedIdentityCredentials $SUBSCRIPTION_ID AzureBlobStorage $INTEGRATION_RUNTIME $STORAGE_ACCOUNT_URI"

    environment = {
      SUBSCRIPTION_ID     = split("/", data.azurerm_subscription.current.id)[2]
      INTEGRATION_RUNTIME = "integration-runtime-azure-managed-vnet"
      STORAGE_ACCOUNT_URI = azurerm_storage_account.adf_st[0].primary_blob_endpoint
    }
  }
}

resource "azurerm_storage_account" "adf_st" {
  count                            = local.adf_subnet_name != null ? 1 : 0
  name                             = "st${var.line_of_business}${var.application_id}${var.environment}${local.short_location_name}adf"
  resource_group_name              = var.data_factory.ud_resource_group != null ? azurerm_resource_group.ud_rgs["${var.data_factory.ud_resource_group}"].name : azurerm_resource_group.adf_rg[0].name
  location                         = var.location
  account_tier                     = "Standard"
  account_replication_type         = "GRS"
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false
  public_network_access_enabled    = false
  tags                             = local.all_tags
  cross_tenant_replication_enabled = false
  # shared_access_key_enabled        = false

  sas_policy {
    expiration_period = "06.23:00:00"
  }
  lifecycle {
    ignore_changes = [
      tags,
      shared_access_key_enabled
    ]
  }
  customer_managed_key {
    key_vault_key_id          = local.base_key_id
    user_assigned_identity_id = azurerm_user_assigned_identity.base_kv_uai[0].id
  }
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.base_kv_uai[0].id]
  }
}

resource "azurerm_private_endpoint" "adf_st_peps" {
  for_each = { for resource in toset(["blob", "web", "file", "table"]) : resource => resource if local.adf_subnet_name != null && var.data_factory.legacy_adf != true }
  # count               = local.adf_subnet_name != null ? 1 : 0
  name                = "pep-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-adfst-${each.key}"
  location            = var.location
  resource_group_name = var.data_factory.ud_resource_group != null ? azurerm_resource_group.ud_rgs["${var.data_factory.ud_resource_group}"].name : azurerm_resource_group.adf_rg[0].name
  subnet_id           = var.data_factory.external_subnet_id != null ? var.data_factory.external_subnet_id : azurerm_subnet.subnets["${var.data_factory.subnet_name}"].id

  private_service_connection {
    name                           = "adfst-privateserviceconnection"
    private_connection_resource_id = azurerm_storage_account.adf_st[0].id
    is_manual_connection           = false
    subresource_names              = [each.key]
  }
  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = self.private_service_connection[0].subresource_names[0] != "web" ? "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.${self.private_service_connection[0].subresource_names[0]}.core.windows.net" : "${split(".", self.custom_dns_configs[0].fqdn)[0]}.${split(".", self.custom_dns_configs[0].fqdn)[1]}.privatelink.${self.private_service_connection[0].subresource_names[0]}.core.windows.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }
}

resource "time_sleep" "adf_st_dns_propagation" {
  depends_on      = [azurerm_private_endpoint.adf_st_peps]
  count           = local.adf_subnet_name != null && var.data_factory.legacy_adf != true ? 1 : 0
  create_duration = "3m"
}
