locals {
  container_registry_ud_mi_container_registry_admin_permissions = flatten([
    for acr_info in var.container_registry : [
      for mi_name in acr_info.ud_mi_container_registry_admin : {
        name         = "ud_mi_container_registry_admin_${acr_info.name}_${mi_name}"
        principal_id = azurerm_user_assigned_identity.ud_managed_identity[mi_name].principal_id
        scope        = azurerm_container_registry.container_registry["${acr_info.name}"].id
      }
    ]
  ])
}

resource "azurerm_container_registry" "container_registry" {
  for_each = { for acr_info in var.container_registry : acr_info.name => acr_info }

  name                          = "acr${var.line_of_business}${var.application_id}${var.environment}${local.short_location_name}${each.value.name}"
  resource_group_name           = azurerm_resource_group.acr_rg[0].name
  location                      = var.location
  sku                           = "Premium"
  admin_enabled                 = each.value.admin_enabled
  public_network_access_enabled = false

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.base_kv_uai[0].id
    ]
  }

  encryption {
    enabled            = true
    key_vault_key_id   = local.base_key_id
    identity_client_id = azurerm_user_assigned_identity.base_kv_uai[0].client_id
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_endpoint" "acr_pes" {
  for_each            = { for acr_info in var.container_registry : acr_info.name => acr_info }
  name                = "pep-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.acr_rg[0].name
  subnet_id           = each.value.external_subnet_id != null ? each.value.external_subnet_id : azurerm_subnet.subnets["${each.value.subnet_name}"].id

  private_service_connection {
    name                           = "${each.value.name}-privateserviceconnection"
    private_connection_resource_id = azurerm_container_registry.container_registry["${each.value.name}"].id
    is_manual_connection           = false
    subresource_names              = ["registry"]
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
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.${var.location}.data.privatelink.azurecr.io"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }
  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.azurecr.io"
      IP       = self.custom_dns_configs[1].ip_addresses[0]
      HOSTNAME = self.custom_dns_configs[1].fqdn
    }
  }
}

# resource "null_resource" "delete_acr_data_pep_dns_when_destroyed" {
#   for_each = { for pep in azurerm_private_endpoint.acr_pes : pep.name => pep }
#   triggers = {
#     working_dir    = local.script_dir
#     delete_command = local.dns_command_delete
#     hostname       = "${split(".", each.value.custom_dns_configs[0].fqdn)[0]}.${var.location}.data.privatelink.azurecr.io"
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

# resource "null_resource" "delete_acr_pep_dns_when_destroyed" {
#   for_each = { for pep in azurerm_private_endpoint.acr_pes : pep.name => pep }
#   triggers = {
#     working_dir    = local.script_dir
#     delete_command = local.dns_command_delete
#     hostname       = "${split(".", each.value.custom_dns_configs[0].fqdn)[0]}.privatelink.azurecr.io"
#     ip_address     = each.value.custom_dns_configs[1].ip_addresses[0]
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