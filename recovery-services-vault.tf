resource "azurerm_recovery_services_vault" "vault" {
  for_each = { for rsv in var.recovery_services_vaults : "${rsv.name}" => rsv }

  name                          = "rsv-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.value.name}"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.backup_rg[0].name
  sku                           = "Standard"
  public_network_access_enabled = false
  storage_mode_type             = each.value.storage_mode_type
  immutability                  = each.value.immutability
  soft_delete_enabled           = false #true can cause errors when enabling replication 
  cross_region_restore_enabled  = each.value.cross_region_restore_enabled


  # CMK with UserAssigned identity not yet supported
  identity {
    type = "SystemAssigned"
    # identity_ids = [azurerm_user_assigned_identity.base_kv_uai[0].id]
  }
  encryption {
    key_id                            = local.base_key_id
    infrastructure_encryption_enabled = false
    # user_assigned_identity_id = azurerm_user_assigned_identity.base_kv_uai[0].id
    use_system_assigned_identity = true
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_role_assignment" "kv_access_rsv" {
  for_each = { for rsv in var.recovery_services_vaults : rsv.name => rsv }

  scope                = local.base_kv_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_recovery_services_vault.vault[each.key].identity.0.principal_id
}

resource "azurerm_private_endpoint" "rsv_pes_bkp" {
  for_each            = { for rsv_info in var.recovery_services_vaults : rsv_info.name => rsv_info }
  name                = "pep-bkp-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.value.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.backup_rg[0].name
  subnet_id           = azurerm_subnet.subnets["${each.value.subnet_name}"].id

  private_service_connection {
    name                           = "${each.value.name}-privateserviceconnection"
    private_connection_resource_id = azurerm_recovery_services_vault.vault["${each.value.name}"].id
    is_manual_connection           = false
    subresource_names              = ["AzureBackup"]
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
      # LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.${split(".", self.custom_dns_configs[0].fqdn)[1]}.privatelink.siterecovery.windowsazure.com"
      LABEL    = self.custom_dns_configs[0].fqdn
      IP       = self.custom_dns_configs[0].ip_addresses[0]
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }
  # AzureBackup PEP requires 2 DNS entries
  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      # LABEL    = "${split(".", self.custom_dns_configs[1].fqdn)[0]}.${split(".", self.custom_dns_configs[1].fqdn)[1]}.privatelink.siterecovery.windowsazure.com"
      LABEL    = self.custom_dns_configs[1].fqdn
      IP       = self.custom_dns_configs[1].ip_addresses[0]
      HOSTNAME = self.custom_dns_configs[1].fqdn
    }
  }
}

# resource "azurerm_private_endpoint" "rsv_pes_asr" {
#   for_each            = { for rsv_info in var.recovery_services_vaults : rsv_info.name => rsv_info }
#   name                = "pep-asr-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.value.name}"
#   location            = var.location
#   resource_group_name = each.value.resource_group != null ? azurerm_resource_group.ud_rgs[each.value.resource_group].name : azurerm_resource_group.rsv_rg[0].name
#   subnet_id           = azurerm_subnet.subnets["${each.value.subnet_name}"].id

#   private_service_connection {
#     name                           = "${each.value.name}-privateserviceconnection"
#     private_connection_resource_id = azurerm_recovery_services_vault.vault["${each.value.name}"].id
#     is_manual_connection           = false
#     subresource_names              = ["AzureSiteRecovery"]
#   }

#   tags = local.all_tags
#   lifecycle {
#     ignore_changes = [
#       tags
#     ]
#   }
#   provisioner "local-exec" {
#     when        = create
#     working_dir = local.script_dir
#     command     = local.dns_command_add

#     environment = {
#       LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.${var.location}.privatelink.siterecovery.windowsazure.com"
#       IP       = self.private_service_connection[0].private_ip_address
#       HOSTNAME = self.custom_dns_configs[0].fqdn
#     }
#   }
# }