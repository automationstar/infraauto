resource "azurerm_api_management" "apim" {
  depends_on = [
    azurerm_key_vault.base_kv
  ]
  for_each = { for apim in var.api_management : apim.name => apim }

  name                 = "apim-${var.line_of_business}-${var.application_id}-${local.env_region}-${each.key}"
  resource_group_name  = azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].name
  location             = var.location
  publisher_name       = each.value.publisher_name
  publisher_email      = each.value.publisher_email
  sku_name             = "${each.value.sku_name}_${each.value.deployed_units}"
  virtual_network_type = each.value.virtual_network_type == "Internal" ? "Internal" : "None"
  public_ip_address_id = each.value.is_stv2 == true ? azurerm_public_ip.apim_public_ip["${each.key}"].id : null
  zones                = each.value.zones

  dynamic "virtual_network_configuration" {
    for_each = each.value.virtual_network_type == "Internal" ? [1] : []
    content {
      subnet_id = each.value.external_subnet_id != null ? each.value.external_subnet_id : azurerm_subnet.subnets["${each.value.subnet_name}"].id
    }
  }

  dynamic "additional_location" {
    for_each = each.value.additional_location != null ? [1] : []
    content {
      location             = each.value.additional_location.location
      capacity             = each.value.additional_location.capacity
      zones                = each.value.additional_location.zones
      gateway_disabled     = each.value.additional_location.gateway_disabled
      public_ip_address_id = azurerm_public_ip.additional_apim_public_ip["${each.key}"].id
      dynamic "virtual_network_configuration" {
        for_each = each.value.additional_location.virtual_network_type == "Internal" ? [1] : []
        content {
          # this value will always be external from another region
          subnet_id = each.value.additional_location.external_subnet_id
        }
      }

    }
  }

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.base_kv_uai[0].id]
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_role_assignment" "kv_access_apim" {
  for_each = { for apim in var.api_management : apim.name => apim }

  scope                = local.base_kv_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_api_management.apim[each.key].identity.0.principal_id
}

resource "azurerm_private_endpoint" "apim_peps" {
  for_each            = { for apim_info in var.api_management : apim_info.name => apim_info if apim_info.virtual_network_type == "pe" }
  name                = "pep-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.value.name}"
  location            = var.location
  resource_group_name = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name : azurerm_resource_group.cog_rg[0].name
  subnet_id           = each.value.external_subnet_id != null ? each.value.external_subnet_id : each.value.subnet_name != null ? azurerm_subnet.subnets[each.value.subnet_name].id : azurerm_subnet.subnets[local.pe_subnet_name].id

  private_service_connection {
    name                           = "${each.value.name}-privateserviceconnection"
    private_connection_resource_id = azurerm_api_management.apim[each.value.name].id
    is_manual_connection           = false
    subresource_names              = ["Gateway"]
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
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.azure-api.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }
}

resource "azurerm_key_vault" "apim_key_vaults" {
  for_each = { for apim in var.api_management : apim.name => apim if apim.kv_subnet_name != null || apim.kv_external_subnet_id != null }

  name                          = var.random_kv_names ? "kv-${var.application_id}${each.key}${random_string.kvname.result}" : "kv-${var.line_of_business}${var.application_id}${local.env_region}${each.key}"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days    = 7
  purge_protection_enabled      = true
  sku_name                      = var.legacy_standard_kv ? each.value.sku_name : "premium"
  enable_rbac_authorization     = true
  public_network_access_enabled = false
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

resource "azurerm_monitor_diagnostic_setting" "diag_apim_keyvault" {
  for_each = { for apim in var.api_management : apim.name => apim if apim.kv_subnet_name != null || apim.kv_external_subnet_id != null }

  name                           = "diag-${azurerm_key_vault.apim_key_vaults[each.key].name}"
  target_resource_id             = azurerm_key_vault.apim_key_vaults[each.key].id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  storage_account_id             = var.diag_storage_account_id
  partner_solution_id            = var.partner_solution_id
  eventhub_authorization_rule_id = local.eventhub_info[local.region_environment].eventhub_authorization_rule_id
  eventhub_name                  = local.eventhub_info[local.region_environment].eventhub_name

  # this enables the Audit Logging on the KV
  enabled_log {
    category_group = "audit"

    retention_policy {
      enabled = false
    }
  }

  # if metrics are not enabled, this must be ignored because it will show up as a change on every run
  lifecycle {
    ignore_changes = [metric]
  }

}

resource "azurerm_private_endpoint" "apim_key_vaults_pes" {
  for_each = { for apim in var.api_management : apim.name => apim if apim.kv_subnet_name != null || apim.kv_external_subnet_id != null }

  name                = "pep-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-kv-${each.value.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].name
  subnet_id           = each.value.kv_external_subnet_id != null ? each.value.kv_external_subnet_id : azurerm_subnet.subnets[each.value.kv_subnet_name].id

  private_service_connection {
    name                           = "${each.value.name}-privateserviceconnection"
    private_connection_resource_id = azurerm_key_vault.apim_key_vaults["${each.value.name}"].id
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

resource "azurerm_role_assignment" "apim_kv_access_for_named_value" {
  for_each = { for apim in var.api_management : apim.name => apim }

  scope                = azurerm_key_vault.apim_key_vaults["${each.value.name}"].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_api_management.apim[each.key].identity.0.principal_id
}

resource "azurerm_role_assignment" "apim_kv_cert_access_for_named_value" {
  for_each = { for apim in var.api_management : apim.name => apim }

  scope                = azurerm_key_vault.apim_key_vaults["${each.value.name}"].id
  role_definition_name = "Key Vault Certificate User"
  principal_id         = azurerm_api_management.apim[each.key].identity.0.principal_id
}

resource "azurerm_public_ip" "apim_public_ip" {
  for_each = { for apim in var.api_management : apim.name => apim if apim.is_stv2 == true }

  name                = "pip-apim-${var.line_of_business}-${var.application_id}-${local.env_region}-${each.key}"
  resource_group_name = azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].name
  location            = var.location
  domain_name_label   = "pip-apim-${var.line_of_business}-${var.application_id}-${local.env_region}-${each.key}"
  allocation_method   = each.value.pip_allocation_method
  sku                 = each.value.pip_sku

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_public_ip" "additional_apim_public_ip" {
  for_each = { for apim in var.api_management : apim.name => apim if (apim.is_stv2 == true && apim.additional_location != null)}

  name                = "pip-apim-${var.line_of_business}-${var.application_id}-${local.location_map[each.value.additional_location.location]}-${each.key}"
  resource_group_name = azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].name
  location            = each.value.additional_location.location
  domain_name_label   = "pip-apim-${var.line_of_business}-${var.application_id}-${local.location_map[each.value.additional_location.location]}-${each.key}"
  allocation_method   = each.value.pip_allocation_method
  sku                 = each.value.pip_sku

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}
