locals {
  st_env_region = var.is_former_st_naming_convention ? "${var.environment}${local.short_location_name}" : local.env_region_code

  st_private_endpoints = flatten([
    for account in var.storage_accounts : [
      for subresource in account.pe_subresources : {
        name                     = account.name
        ud_resource_group        = account.ud_resource_group
        account_tier             = account.account_tier
        account_replication_type = account.account_replication_type
        subnet_name              = account.subnet_name
        subresource              = subresource
        cmk_id                   = account.cmk_id
        cmk_managed_identity_id  = account.cmk_managed_identity_id
      }
    ]
  ])

  # diag_st_private_endpoints = var.deploy_diag_storage && var.storage_account_subnet != null ? var.diag_st_private_endpoints_subresource_types : []
}

resource "azurerm_storage_account" "diag_storage_account" {
  count = var.deploy_diag_storage ? 1 : 0

  name                             = "st${var.line_of_business}${var.application_id}${local.st_env_region}diag"
  resource_group_name              = azurerm_resource_group.diag_rg[0].name
  location                         = azurerm_resource_group.diag_rg[0].location
  account_tier                     = "Standard"
  account_replication_type         = "GRS"
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false
  public_network_access_enabled    = false
  cross_tenant_replication_enabled = false
  # shared_access_key_enabled = false

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags,
      shared_access_key_enabled
    ]
  }
  sas_policy {
    expiration_period = "06.23:00:00"
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


resource "azurerm_private_endpoint" "diag_storage_account_pes" {
  count = var.deploy_diag_storage ? 1 : 0

  name                = "pep-${azurerm_storage_account.diag_storage_account[0].name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.diag_rg[0].name
  subnet_id           = azurerm_subnet.subnets[local.pe_subnet_name].id

  private_service_connection {
    name                           = "${azurerm_storage_account.diag_storage_account[0].name}-privateserviceconnection"
    private_connection_resource_id = azurerm_storage_account.diag_storage_account[0].id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.${self.private_service_connection[0].subresource_names[0]}.core.windows.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  tags = local.all_tags
}

# resource "azurerm_storage_account_customer_managed_key" "adf_storage_account_cmk" {

#   count = local.adf_subnet_name != null ? 1 : 0

#   storage_account_id        = azurerm_storage_account.adf_st[0].id
#   key_vault_id              = local.base_kv_id
#   key_name                  = azurerm_key_vault_key.base_kv_key[0].name
#   user_assigned_identity_id = azurerm_user_assigned_identity.base_kv_uai[0].id
# }


resource "azurerm_storage_account" "ud_storage_accounts" {
  depends_on = [time_sleep.base_kv_role_propagation]
  for_each   = { for st in var.storage_accounts : "${st.name}" => st }

  name                             = "st${var.line_of_business}${var.application_id}${local.st_env_region}${each.value.name}"
  resource_group_name              = azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].name
  location                         = azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].location
  account_tier                     = each.value.account_tier
  account_replication_type         = each.value.account_replication_type
  account_kind                     = each.value.account_kind
  min_tls_version                  = "TLS1_2"
  is_hns_enabled                   = each.value.hns_enabled
  allow_nested_items_to_be_public  = false
  public_network_access_enabled    = each.value.public_network_access_enabled
  sftp_enabled                     = each.value.sftp_enabled
  cross_tenant_replication_enabled = false
  # shared_access_key_enabled = false
  sas_policy {
    expiration_period = each.value.sas_expiration_period
  }
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.base_kv_uai[0].id]
  }
  customer_managed_key {
    key_vault_key_id          = local.base_key_id
    user_assigned_identity_id = azurerm_user_assigned_identity.base_kv_uai[0].id
  }

  dynamic "custom_domain" {
    for_each = each.value.custom_domain != null ? [1] : []

    content {
      name          = each.value.custom_domain
      use_subdomain = each.value.use_subdomain
    }

  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags,
      shared_access_key_enabled
    ]
  }
}
# resource "azurerm_storage_account_customer_managed_key" "ud_storage_account_cmks" {

#   for_each = { for st in var.storage_accounts : "${st.name}" => st}

#   storage_account_id = azurerm_storage_account.ud_storage_accounts["${each.value.name}"].id
#   key_vault_id = local.base_kv_id
#   key_name = azurerm_key_vault_key.base_kv_key[0].name
#   user_assigned_identity_id = azurerm_user_assigned_identity.base_kv_uai[0].id
# }

resource "azurerm_storage_account_network_rules" "st_ntwk_rules" {
  for_each = { for st in var.storage_accounts : "${st.name}" => st }

  storage_account_id = azurerm_storage_account.ud_storage_accounts["${each.key}"].id
  default_action     = "Deny"

  lifecycle {
    ignore_changes = [
      private_link_access
    ]
  }
}

resource "azurerm_private_endpoint" "ud_storage_accounts_pes" {
  for_each = { for st in local.st_private_endpoints : "${st.name}-${st.subresource}" => st }

  name                = "pep-${each.value.subresource}-${azurerm_storage_account.ud_storage_accounts["${each.value.name}"].name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name
  subnet_id           = azurerm_subnet.subnets[each.value.subnet_name].id

  private_service_connection {
    name                           = "${each.value.name}-privateserviceconnection"
    private_connection_resource_id = azurerm_storage_account.ud_storage_accounts[each.value.name].id
    is_manual_connection           = false
    subresource_names              = [each.value.subresource]
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

# resource "null_resource" "delete_st_pep_dns_when_destroyed" {
#   for_each = { for pep in azurerm_private_endpoint.ud_storage_accounts_pes : pep.name => pep }
#   triggers = {
#     working_dir    = local.script_dir
#     delete_command = local.dns_command_delete
#     hostname       = each.value.private_service_connection[0].subresource_names[0] != "web" ? "${split(".", each.value.custom_dns_configs[0].fqdn)[0]}.privatelink.${each.value.private_service_connection[0].subresource_names[0]}.core.windows.net" : "${split(".", each.value.custom_dns_configs[0].fqdn)[0]}.${split(".", each.value.custom_dns_configs[0].fqdn)[1]}.privatelink.${each.value.private_service_connection[0].subresource_names[0]}.core.windows.net"
#     ip_address     = each.value.private_service_connection[0].private_ip_address
#   }

#   provisioner "local-exec" {
#     when        = destroy
#     working_dir = self.triggers.working_dir
#     command     = self.triggers.delete_command
#     environment = {
#       LABEL = self.triggers.hostname
#       IP       = self.triggers.ip_address
#     }
#   }
# }
