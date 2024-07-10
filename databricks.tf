locals {
  dbk_private_endpoints = flatten([
    for dbk in var.databricks : [
      for subresource in dbk.pe_subresources : {
        name                     = dbk.name
        ud_resource_group        = dbk.ud_resource_group
        sku                      = dbk.sku
        storage_account_sku_name = dbk.storage_account_sku_name
        public_subnet_name       = dbk.public_subnet_name
        subresource              = subresource
        private_subnet_name      = dbk.private_subnet_name
        pe_subnet_name           = dbk.pe_subnet_name
        external_subnet_id       = dbk.external_subnet_id
      }
    ]
  ])

}

resource "azurerm_role_assignment" "base_kv_key_access_admin_role_dbk" {
  count                = length(var.databricks) > 0 ? 1 : 0
  scope                = local.base_kv_id
  role_definition_name = "Key Vault Administrator"
  # Default Azure Databricks ID for all tenants
  principal_id = "7b8a316d-376e-4fef-8a36-ff56c2076a98"
}

resource "azurerm_databricks_workspace" "dbk" {
  depends_on = [
    azurerm_network_security_rule.network_security_rules,
    azurerm_role_assignment.base_kv_key_access_admin_role_dbk
  ]
  for_each = { for dbw in var.databricks : dbw.name => dbw }

  name                                  = each.value.import_dbk == false ? "dbw-${var.line_of_business}${var.application_id}${local.env_region}${each.key}" : each.value.import_dbk_name
  resource_group_name                   = azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name
  location                              = var.location
  sku                                   = each.value.sku
  network_security_group_rules_required = "NoAzureDatabricksRules"
  public_network_access_enabled         = false
  managed_resource_group_name           = "managed-dbw-${var.line_of_business}${var.application_id}${local.env_region}${each.key}"

  custom_parameters {
    public_subnet_name                                   = azurerm_subnet.subnets[each.value.public_subnet_name].name
    private_subnet_name                                  = azurerm_subnet.subnets[each.value.private_subnet_name].name
    public_subnet_network_security_group_association_id  = azurerm_network_security_group.network_security_group[0].id
    private_subnet_network_security_group_association_id = azurerm_network_security_group.network_security_group[0].id
    storage_account_name                                 = each.value.import_dbk == false ? substr("mgdst${each.key}${var.line_of_business}${var.application_id}${local.env_region}", 0, 23) : substr(each.value.import_dbk_storage_account_name, 0, 23)
    storage_account_sku_name                             = each.value.storage_account_sku_name
    virtual_network_id                                   = local.vnet_id
    no_public_ip                                         = true
  }

  customer_managed_key_enabled          = each.value.sku == "premium" ? true : false
  managed_services_cmk_key_vault_key_id = each.value.sku == "premium" ? local.base_key_id : null
  managed_disk_cmk_key_vault_key_id     = each.value.sku == "premium" ? local.base_key_id : null
  infrastructure_encryption_enabled     = each.value.sku == "premium" ? true : false

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_role_assignment" "base_kv_key_access_dbw_managed_id" {
  for_each = { for dbw in var.databricks : dbw.name => dbw }

  scope                = local.base_kv_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_databricks_workspace.dbk[each.key].managed_disk_identity[0].principal_id
}


resource "azurerm_monitor_diagnostic_setting" "diag_dbk" {
  for_each = { for dbw in var.databricks : dbw.name => dbw if dbw.sku == "premium" }

  name                           = "diag-${azurerm_databricks_workspace.dbk[each.key].name}"
  target_resource_id             = azurerm_databricks_workspace.dbk[each.key].id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  storage_account_id             = var.diag_storage_account_id
  partner_solution_id            = var.partner_solution_id
  eventhub_authorization_rule_id = local.eventhub_info[local.region_environment].eventhub_authorization_rule_id
  eventhub_name                  = local.eventhub_info[local.region_environment].eventhub_name

  enabled_log {
    category_group = "allLogs"

    retention_policy {
      enabled = false
    }
  }


  # if metrics are not enabled, this must be ignored because it will show up as a change on every run
  lifecycle {
    ignore_changes = [metric]
  }


}

resource "azurerm_private_endpoint" "dbk_pes" {
  for_each = { for dbw in local.dbk_private_endpoints : "${dbw.name}-${dbw.subresource}" => dbw if dbw.sku == "premium" && (dbw.pe_subnet_name != null || dbw.external_subnet_id == null) }

  name                = "pep-${each.value.subresource}-${azurerm_databricks_workspace.dbk[each.value.name].name}"
  resource_group_name = azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name
  location            = var.location
  subnet_id           = each.value.external_subnet_id != null ? each.value.external_subnet_id : each.value.pe_subnet_name != null ? azurerm_subnet.subnets[each.value.pe_subnet_name].id : azurerm_subnet.subnets[local.pe_subnet_name].id

  private_service_connection {
    name                           = "${each.value.name}-privateserviceconnection"
    private_connection_resource_id = azurerm_databricks_workspace.dbk[each.value.name].id
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
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.${split(".", self.custom_dns_configs[0].fqdn)[1]}.privatelink.azuredatabricks.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }
}

# resource "null_resource" "delete_dbk_pep_dns_when_destroyed" {
#   for_each = { for pep in azurerm_private_endpoint.dbk_pes : pep.name => pep }
#   triggers = {
#     working_dir    = local.script_dir
#     delete_command = local.dns_command_delete
#     hostname       = "${split(".", each.value.custom_dns_configs[0].fqdn)[0]}.${split(".", each.value.custom_dns_configs[0].fqdn)[1]}.privatelink.azuredatabricks.net"
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