data "azurerm_resources" "ases" {
  for_each = { for app_info in var.app_service_plans : app_info.name => app_info if app_info.ase_name != null }

  name                = each.value.ase_name
  resource_group_name = each.value.ase_rg
}

resource "azurerm_app_service_environment_v3" "ases" {
  for_each = { for name, subnet in local.subnets_with_delegation_info : name => subnet if subnet.type == "app_service_env" }

  name                = "ase-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.key}"
  resource_group_name = azurerm_resource_group.app_services_rg[0].name
  subnet_id           = azurerm_subnet.subnets["${each.value.name}"].id

  internal_load_balancing_mode = "Web, Publishing"

  dynamic "cluster_setting" {
    for_each = var.ase_internal_encryption == true ? [1] : []
    content {
      name = "InternalEncryption"
      value = "true"
    }
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
      LABEL    = "*.${self.dns_suffix}"
      IP       = self.internal_inbound_ip_addresses[0]
      HOSTNAME = "*.${self.dns_suffix}"
    }
  }

  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = "*.scm.${self.dns_suffix}"
      IP       = self.internal_inbound_ip_addresses[0]
      HOSTNAME = "*.scm.${self.dns_suffix}"
    }
  }

}

resource "azurerm_service_plan" "asps" {
  for_each = { for app_info in var.app_service_plans : app_info.name => app_info }

  name                       = "asp-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.key}"
  resource_group_name        = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].name : azurerm_resource_group.app_services_rg[0].name
  location                   = var.location
  os_type                    = each.value.os_type
  sku_name                   = each.value.sku_name
  app_service_environment_id = each.value.subnet_name != null ? azurerm_app_service_environment_v3.ases["${each.value.subnet_name}"].id : (each.value.ase_name != null ? data.azurerm_resources.ases["${each.value.name}"].resources[0].id : null)

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

locals {
  linux_asps    = { for app_info in var.app_service_plans : app_info.name => app_info if app_info.os_type == "Linux" }
  linux_funapps = [for funapp in var.function_apps : funapp if lookup(local.linux_asps, funapp.ud_app_service_plan, null) != null]
  linux_webapps = [for webapp in var.web_apps : webapp if lookup(local.linux_asps, webapp.ud_app_service_plan, null) != null]

  windows_asps    = { for app_info in var.app_service_plans : app_info.name => app_info if app_info.os_type == "Windows" }
  windows_funapps = [for funapp in var.function_apps : funapp if lookup(local.windows_asps, funapp.ud_app_service_plan, null) != null]
  windows_webapps = [for webapp in var.web_apps : webapp if lookup(local.windows_asps, webapp.ud_app_service_plan, null) != null]


}

locals {
  app_settings = {
    "WEBSITE_CONTENTOVERVNET" = "1"
    "WEBSITE_VNET_ROUTE_ALL"  = "1"
    "WEBSITE_DNS_SERVER"      = local.dns_servers[var.location][0]
    "WEBSITE_DNS_ALT_SERVER"  = local.dns_servers[var.location][1]
  }
}

data "azurerm_user_assigned_identity" "function_uais" {
  for_each = { for app in var.function_apps : app.name => app if app.user_identity_name != null }

  name                = each.value.user_identity_name
  resource_group_name = each.value.user_identity_resource_group
}

data "azurerm_user_assigned_identity" "web_uais" {
  for_each = { for app in var.web_apps : app.name => app if app.user_identity_name != null }

  name                = each.value.user_identity_name
  resource_group_name = each.value.user_identity_resource_group
}

resource "azurerm_monitor_autoscale_setting" "asp_autoscale" {
  for_each = { for app_info in var.app_service_plans : app_info.name => app_info if app_info.autoscale == true }

  name                = "autoscale-${each.key}"
  resource_group_name = azurerm_service_plan.asps[each.key].resource_group_name
  location            = azurerm_service_plan.asps[each.key].location
  target_resource_id  = azurerm_service_plan.asps[each.key].id

  profile {
    name = "defaultProfile"

    capacity {
      default = each.value.min_instances
      minimum = each.value.min_instances
      maximum = each.value.max_instances
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.asps[each.key].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = each.value.scale_up_threshold
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.asps[each.key].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = each.value.scale_down_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }

  lifecycle {
    ignore_changes = [
      tags,
      profile # This tells Terraform to ignore future changes to the `profile` attribute for asp auto_scaling_settings
    ]
  }

}

resource "azurerm_logic_app_standard" "logicapps" {
  depends_on = [azurerm_private_endpoint.ud_storage_accounts_pes]
  for_each   = { for logicapp in var.logic_apps : logicapp.name => logicapp }

  name                       = "logic-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.key}"
  location                   = var.location
  resource_group_name        = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].name : azurerm_resource_group.app_services_rg[0].name
  app_service_plan_id        = azurerm_service_plan.asps[each.value.ud_app_service_plan].id
  storage_account_name       = azurerm_storage_account.ud_storage_accounts[each.value.ud_storage_account].name
  storage_account_access_key = azurerm_storage_account.ud_storage_accounts[each.value.ud_storage_account].primary_access_key
  https_only                 = true
  virtual_network_subnet_id  = each.value.integrated_subnet_name != null ? azurerm_subnet.subnets[each.value.integrated_subnet_name].id : each.value.external_integrated_subnet_id

  identity {
    type = "SystemAssigned"
  }

  dynamic "site_config" {
    for_each = [each.value.site_config]
    content {
      always_on                = false
      dotnet_framework_version = lookup(each.value.site_config, "dotnet_framework_version", null)

      dynamic "cors" {
        for_each = lookup(site_config.value, "cors", null) == null ? [] : ["cors"]
        content {
          allowed_origins     = each.value.site_config.cors.allowed_origins
          support_credentials = each.value.site_config.cors.support_credentials
        }
      }
    }
  }

  tags = local.all_tags

  app_settings = merge(local.app_settings, each.value.app_settings)

  lifecycle {
    ignore_changes = [
      tags,
      app_settings,
      site_config["application_insights_connection_string"],
      site_config["application_insights_key"],
      site_config["ftps_state"],
      site_config["application_stack"],
      site_config["app_command_line"],
      site_config["cors"],
    ]
  }


}

resource "azurerm_private_endpoint" "logicapps_pe" {
  for_each            = { for logicapp in var.logic_apps : logicapp.name => logicapp if logicapp.pe_subnet_name != null || logicapp.external_pe_subnet_id != null }
  name                = "pep-${azurerm_logic_app_standard.logicapps[each.key].name}"
  location            = var.location
  resource_group_name = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].name : azurerm_resource_group.app_services_rg[0].name
  subnet_id           = each.value.external_pe_subnet_id != null ? each.value.external_pe_subnet_id : azurerm_subnet.subnets[each.value.pe_subnet_name].id

  private_service_connection {
    name                           = lower("pep-${azurerm_logic_app_standard.logicapps[each.key].name}")
    private_connection_resource_id = azurerm_logic_app_standard.logicapps[each.key].id
    is_manual_connection           = false
    subresource_names              = ["sites"]
  }

  tags = local.all_tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }

  # DNS for accessing the website
  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.azurewebsites.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }

  # DNS for deployments
  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.scm.privatelink.azurewebsites.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }
}

resource "azurerm_linux_function_app" "linux_funapps" {
  for_each = { for funapp in local.linux_funapps : funapp.name => funapp }

  name                          = "func-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.key}"
  location                      = var.location
  resource_group_name           = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].name : azurerm_resource_group.app_services_rg[0].name
  service_plan_id               = azurerm_service_plan.asps[each.value.ud_app_service_plan].id
  storage_account_name          = azurerm_storage_account.ud_storage_accounts[each.value.ud_storage_account].name
  storage_account_access_key    = azurerm_storage_account.ud_storage_accounts[each.value.ud_storage_account].primary_access_key
  https_only                    = true
  public_network_access_enabled = each.value.public_network_access_enabled
  virtual_network_subnet_id     = each.value.integrated_subnet_name != null ? azurerm_subnet.subnets[each.value.integrated_subnet_name].id : each.value.external_integrated_subnet_id

  dynamic "site_config" {
    for_each = [each.value.site_config]
    content {
      minimum_tls_version = 1.2
      dynamic "application_stack" {
        for_each = lookup(site_config.value, "application_stack", null) == null ? [] : ["application_stack"]
        content {
          dynamic "docker" {
            for_each = lookup(each.value.site_config.application_stack, "docker", null) == null ? [] : ["docker"]
            content {
              registry_url      = each.value.site_config.application_stack.docker.registry_url
              image_name        = each.value.site_config.application_stack.docker.image_name
              image_tag         = each.value.site_config.application_stack.docker.image_tag
              registry_username = lookup(each.value.site_config.application_stack.docker, "registry_username", null)
              registry_password = lookup(each.value.site_config.application_stack.docker, "registry_password", null)
            }
          }
          dotnet_version              = lookup(each.value.site_config.application_stack, "dotnet_version", null)
          use_dotnet_isolated_runtime = lookup(each.value.site_config.application_stack, "use_dotnet_isolated_runtime", null)
          java_version                = lookup(each.value.site_config.application_stack, "java_version", null)
          node_version                = lookup(each.value.site_config.application_stack, "node_version", null)
          python_version              = lookup(each.value.site_config.application_stack, "python_version", null)
          powershell_core_version     = lookup(each.value.site_config.application_stack, "powershell_core_version", null)
          use_custom_runtime          = lookup(each.value.site_config.application_stack, "use_custom_runtime", null)
        }
      }
    }
  }

  dynamic "identity" {
    for_each = each.value.ud_user_identity != null || each.value.user_identity_name != null ? [1] : []
    content {
      type         = "SystemAssigned, UserAssigned"
      identity_ids = [each.value.user_identity_name != null ? data.azurerm_user_assigned_identity.function_uais[each.key].id : azurerm_user_assigned_identity.ud_managed_identity[each.value.ud_user_identity].id]
    }
  }

  dynamic "identity" {
    for_each = each.value.ud_user_identity == null && each.value.user_identity_name == null ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  tags = local.all_tags

  lifecycle {
    ignore_changes = [
      tags,
      app_settings,
      sticky_settings,
      site_config["application_insights_connection_string"],
      site_config["application_insights_key"],
      site_config["ftps_state"],
      site_config["application_stack"],
      site_config["app_command_line"],
      site_config["cors"]
    ]
  }
}

resource "azurerm_role_assignment" "kv_access_linux_funapps" {
  for_each = { for funapp in local.linux_funapps : funapp.name => funapp }

  scope                = local.base_kv_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.linux_funapps[each.key].identity.0.principal_id
}

resource "azurerm_private_endpoint" "linux_funapps_pe" {
  for_each            = { for funapp in local.linux_funapps : funapp.name => funapp if funapp.pe_subnet_name != null || funapp.external_pe_subnet_id != null }
  name                = "pep-${azurerm_linux_function_app.linux_funapps[each.key].name}"
  location            = var.location
  resource_group_name = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].name : azurerm_resource_group.app_services_rg[0].name
  subnet_id           = each.value.external_pe_subnet_id != null ? each.value.external_pe_subnet_id : azurerm_subnet.subnets[each.value.pe_subnet_name].id

  private_service_connection {
    name                           = lower("pep-${azurerm_linux_function_app.linux_funapps[each.key].name}")
    private_connection_resource_id = azurerm_linux_function_app.linux_funapps[each.key].id
    is_manual_connection           = false
    subresource_names              = ["sites"]
  }

  tags = local.all_tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }

  # DNS for accessing the website
  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.azurewebsites.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }

  # DNS for deployments
  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.scm.privatelink.azurewebsites.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }
}

resource "azurerm_windows_function_app" "windows_funapps" {
  for_each = { for funapp in local.windows_funapps : funapp.name => funapp }

  name                          = "func-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.key}"
  location                      = var.location
  resource_group_name           = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].name : azurerm_resource_group.app_services_rg[0].name
  service_plan_id               = azurerm_service_plan.asps[each.value.ud_app_service_plan].id
  storage_account_name          = azurerm_storage_account.ud_storage_accounts[each.value.ud_storage_account].name
  storage_account_access_key    = azurerm_storage_account.ud_storage_accounts[each.value.ud_storage_account].primary_access_key
  https_only                    = true
  public_network_access_enabled = each.value.public_network_access_enabled
  virtual_network_subnet_id     = each.value.integrated_subnet_name != null ? azurerm_subnet.subnets[each.value.integrated_subnet_name].id : each.value.external_integrated_subnet_id

  dynamic "site_config" {
    for_each = [each.value.site_config]
    content {
      minimum_tls_version = 1.2
      dynamic "application_stack" {
        for_each = lookup(site_config.value, "application_stack", null) == null ? [] : ["application_stack"]
        content {
          dotnet_version              = lookup(each.value.site_config.application_stack, "dotnet_version", null)
          use_dotnet_isolated_runtime = lookup(each.value.site_config.application_stack, "use_dotnet_isolated_runtime", null)
          java_version                = lookup(each.value.site_config.application_stack, "java_version", null)
          node_version                = lookup(each.value.site_config.application_stack, "node_version", null)
          powershell_core_version     = lookup(each.value.site_config.application_stack, "powershell_core_version", null)
          use_custom_runtime          = lookup(each.value.site_config.application_stack, "use_custom_runtime", null)
        }
      }
    }
  }
  dynamic "identity" {
    for_each = each.value.ud_user_identity != null || each.value.user_identity_name != null ? [1] : []
    content {
      type         = "SystemAssigned, UserAssigned"
      identity_ids = [each.value.user_identity_name != null ? data.azurerm_user_assigned_identity.function_uais[each.key].id : azurerm_user_assigned_identity.ud_managed_identity[each.value.ud_user_identity].id]
    }
  }

  dynamic "identity" {
    for_each = each.value.ud_user_identity == null && each.value.user_identity_name == null ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags,
      app_settings,
      sticky_settings,
      site_config["application_insights_connection_string"],
      site_config["application_insights_key"],
      site_config["ftps_state"],
      site_config["application_stack"],
      site_config["app_command_line"],
      site_config["cors"]
    ]
  }
}

resource "azurerm_role_assignment" "kv_access_windows_funapps" {
  for_each = { for funapp in local.windows_funapps : funapp.name => funapp }

  scope                = local.base_kv_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_windows_function_app.windows_funapps[each.key].identity.0.principal_id
}

resource "azurerm_private_endpoint" "windows_funapps_pe" {
  for_each            = { for funapp in local.windows_funapps : funapp.name => funapp if funapp.pe_subnet_name != null || funapp.external_pe_subnet_id != null }
  name                = "pep-${azurerm_windows_function_app.windows_funapps[each.key].name}"
  location            = var.location
  resource_group_name = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].name : azurerm_resource_group.app_services_rg[0].name
  subnet_id           = each.value.external_pe_subnet_id != null ? each.value.external_pe_subnet_id : azurerm_subnet.subnets[each.value.pe_subnet_name].id

  private_service_connection {
    name                           = lower("pep-${azurerm_windows_function_app.windows_funapps[each.key].name}")
    private_connection_resource_id = azurerm_windows_function_app.windows_funapps[each.key].id
    is_manual_connection           = false
    subresource_names              = ["sites"]
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }

  # DNS for accessing the website
  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.azurewebsites.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }

  # DNS for deployments
  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.scm.privatelink.azurewebsites.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }
}

resource "azurerm_app_configuration" "appconfs" {
  for_each = { for appconf in var.app_configurations : appconf.name => appconf }

  name                       = var.random_kv_names ? "appcs-${var.line_of_business}-${var.application_id}-${each.key}-${random_string.kvname.result}" : "appcs-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.key}"
  resource_group_name        = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name : azurerm_resource_group.app_services_rg[0].name
  location                   = var.location
  sku                        = "standard"
  public_network_access      = "Disabled"
  local_auth_enabled         = each.value.local_auth_enabled
  purge_protection_enabled   = true
  soft_delete_retention_days = 7

  identity {
    type = "UserAssigned"
    identity_ids = [
      azurerm_user_assigned_identity.base_kv_uai[0].id
    ]
  }

  encryption {
    key_vault_key_identifier = local.base_key_id
    identity_client_id       = azurerm_user_assigned_identity.base_kv_uai[0].client_id
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }

}

resource "azurerm_private_endpoint" "app_conf_pe" {
  for_each = { for appconf in var.app_configurations : appconf.name => appconf }

  name                = "pep-${azurerm_app_configuration.appconfs[each.key].name}"
  resource_group_name = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name : azurerm_resource_group.app_services_rg[0].name
  location            = var.location
  subnet_id           = each.value.external_subnet_id != null ? each.value.external_subnet_id : azurerm_subnet.subnets[each.value.subnet_name].id

  private_service_connection {
    name                           = lower("pep-${azurerm_app_configuration.appconfs[each.key].name}")
    private_connection_resource_id = azurerm_app_configuration.appconfs[each.key].id
    is_manual_connection           = false
    subresource_names              = ["configurationStores"]
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
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.azconfig.io"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }
}

# resource "azurerm_role_assignment" "app_conf_access" {
#   for_each = { for appconf in var.app_configurations : appconf.name => appconf }

#   scope                = azurerm_app_configuration.appconfs[each.value.name].id
#   role_definition_name = "App Configuration Data Owner"
#   principal_id         = data.azurerm_client_config.current.object_id
# }


resource "azurerm_application_insights" "windows_webapps_app_insights" {
  for_each = { for webapp in local.windows_webapps : webapp.name => webapp }

  name                = "appi-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.key}"
  location            = var.location
  resource_group_name = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name : azurerm_resource_group.app_services_rg[0].name
  workspace_id        = var.log_analytics_workspace != "none" ? azurerm_log_analytics_workspace.log_analytics_workspace[0].id : null
  application_type    = each.value.application_type

  daily_data_cap_in_gb = each.value.app_insights_daily_data_cap_in_gb
  retention_in_days    = each.value.app_insights_retention_in_days

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_windows_web_app" "windows_webapps" {
  for_each = { for webapp in local.windows_webapps : webapp.name => webapp }

  name                          = "app-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.key}"
  location                      = var.location
  resource_group_name           = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name : azurerm_resource_group.app_services_rg[0].name
  service_plan_id               = azurerm_service_plan.asps[each.value.ud_app_service_plan].id
  https_only                    = true
  public_network_access_enabled = each.value.public_network_access_enabled
  virtual_network_subnet_id     = each.value.disable_vnet_integration == true ? null : (each.value.integrated_subnet_name != null ? azurerm_subnet.subnets[each.value.integrated_subnet_name].id : each.value.external_integrated_subnet_id)

  dynamic "site_config" {
    for_each = [each.value.site_config]
    content {
      minimum_tls_version = 1.2
      dynamic "application_stack" {
        for_each = lookup(site_config.value, "application_stack", null) == null ? [] : ["application_stack"]
        content {
          current_stack             = lookup(each.value.site_config.application_stack, "current_stack", null)
          docker_container_name     = lookup(each.value.site_config.application_stack, "docker_container_name", null)
          docker_container_registry = lookup(each.value.site_config.application_stack, "docker_container_registry", null)
          docker_container_tag      = lookup(each.value.site_config.application_stack, "docker_container_tag", null)
          dotnet_version            = lookup(each.value.site_config.application_stack, "dotnet_version", null)
          dotnet_core_version       = lookup(each.value.site_config.application_stack, "dotnet_core_version", null)
          tomcat_version            = lookup(each.value.site_config.application_stack, "tomcat_version", null)
          java_version              = lookup(each.value.site_config.application_stack, "java_version", null)
          node_version              = lookup(each.value.site_config.application_stack, "node_version", null)
          php_version               = lookup(each.value.site_config.application_stack, "php_version", null)
          python                    = lookup(each.value.site_config.application_stack, "python", null)
        }
      }
    }
  }

  dynamic "identity" {
    for_each = each.value.ud_user_identity != null || each.value.user_identity_name != null ? [1] : []
    content {
      type         = "SystemAssigned, UserAssigned"
      identity_ids = [each.value.user_identity_name != null ? data.azurerm_user_assigned_identity.web_uais[each.key].id : azurerm_user_assigned_identity.ud_managed_identity[each.value.ud_user_identity].id]
    }
  }

  dynamic "identity" {
    for_each = each.value.ud_user_identity == null && each.value.user_identity_name == null ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  app_settings = merge({
    "APPINSIGHTS_INSTRUMENTATIONKEY"             = azurerm_application_insights.windows_webapps_app_insights[each.key].instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING"      = azurerm_application_insights.windows_webapps_app_insights[each.key].connection_string
    "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
  }, each.value.app_settings)

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags,
      auth_settings,
      auth_settings_v2,
      app_settings,
      site_config["cors"],
      logs
    ]
  }

}

resource "azurerm_private_endpoint" "windows_webapps_pe" {
  for_each            = { for webapp in local.windows_webapps : webapp.name => webapp if webapp.subnet_name != null || webapp.external_subnet_id != null }
  name                = "pep-${azurerm_windows_web_app.windows_webapps[each.key].name}"
  location            = var.location
  resource_group_name = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name : azurerm_resource_group.app_services_rg[0].name
  subnet_id           = each.value.external_subnet_id != null ? each.value.external_subnet_id : azurerm_subnet.subnets[each.value.subnet_name].id

  private_service_connection {
    name                           = lower("pep-${azurerm_windows_web_app.windows_webapps[each.key].name}")
    private_connection_resource_id = azurerm_windows_web_app.windows_webapps[each.key].id
    is_manual_connection           = false
    subresource_names              = ["sites"]
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }

  # DNS for accessing the website
  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.azurewebsites.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }

  # DNS for deployments
  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.scm.privatelink.azurewebsites.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }
}

resource "azurerm_application_insights" "linux_webapps_app_insights" {
  for_each = { for webapp in local.linux_webapps : webapp.name => webapp }

  name                = "appi-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.key}"
  location            = var.location
  resource_group_name = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name : azurerm_resource_group.app_services_rg[0].name
  workspace_id        = var.log_analytics_workspace != "none" ? azurerm_log_analytics_workspace.log_analytics_workspace[0].id : null
  application_type    = each.value.application_type

  daily_data_cap_in_gb = each.value.app_insights_daily_data_cap_in_gb
  retention_in_days    = each.value.app_insights_retention_in_days

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_linux_web_app" "linux_webapps" {
  for_each = { for webapp in local.linux_webapps : webapp.name => webapp }

  name                          = "app-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.key}"
  location                      = var.location
  resource_group_name           = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name : azurerm_resource_group.app_services_rg[0].name
  service_plan_id               = azurerm_service_plan.asps[each.value.ud_app_service_plan].id
  https_only                    = true
  public_network_access_enabled = each.value.public_network_access_enabled
  virtual_network_subnet_id     = each.value.disable_vnet_integration == true ? null : (each.value.integrated_subnet_name != null ? azurerm_subnet.subnets[each.value.integrated_subnet_name].id : each.value.external_integrated_subnet_id)

  dynamic "site_config" {
    for_each = [each.value.site_config]
    content {
      minimum_tls_version = 1.2
      dynamic "application_stack" {
        for_each = lookup(site_config.value, "application_stack", null) == null ? [] : ["application_stack"]
        content {
          docker_image_name   = lookup(each.value.site_config.application_stack, "docker_image_name", null)   ## includes tag example: appsvc/staticsite:latest
          docker_registry_url = lookup(each.value.site_config.application_stack, "docker_registry_url", null) ## url of docker_image_name example: https://mcr.microsoft.com (required for docker_image_name)
          dotnet_version      = lookup(each.value.site_config.application_stack, "dotnet_version", null)
          go_version          = lookup(each.value.site_config.application_stack, "go_version", null)
          java_server_version = lookup(each.value.site_config.application_stack, "java_server_version", null)
          java_version        = lookup(each.value.site_config.application_stack, "java_version", null)
          java_server         = lookup(each.value.site_config.application_stack, "java_server", null)
          node_version        = lookup(each.value.site_config.application_stack, "node_version", null)
          php_version         = lookup(each.value.site_config.application_stack, "php_version", null)
          python_version      = lookup(each.value.site_config.application_stack, "python_version", null)
          ruby_version        = lookup(each.value.site_config.application_stack, "ruby_version", null)
        }
      }
    }
  }

  app_settings = merge({
    "APPINSIGHTS_INSTRUMENTATIONKEY"             = azurerm_application_insights.linux_webapps_app_insights[each.key].instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING"      = azurerm_application_insights.linux_webapps_app_insights[each.key].connection_string
    "ApplicationInsightsAgent_EXTENSION_VERSION" = "~3"
  }, each.value.app_settings)

  dynamic "identity" {
    for_each = each.value.ud_user_identity != null || each.value.user_identity_name != null ? [1] : []
    content {
      type         = "SystemAssigned, UserAssigned"
      identity_ids = [each.value.user_identity_name != null ? data.azurerm_user_assigned_identity.web_uais[each.key].id : azurerm_user_assigned_identity.ud_managed_identity[each.value.ud_user_identity].id]
    }
  }
  dynamic "identity" {
    for_each = each.value.ud_user_identity == null && each.value.user_identity_name == null ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags,
      app_settings,
      auth_settings,
      auth_settings_v2,
      sticky_settings,
      site_config["application_insights_connection_string"],
      site_config["application_insights_key"],
      site_config["ftps_state"],
      site_config["application_stack"],
      site_config["app_command_line"],
      site_config["cors"]
    ]
  }
}

resource "azurerm_private_endpoint" "linux_webapps_pe" {
  for_each            = { for webapp in local.linux_webapps : webapp.name => webapp if webapp.subnet_name != null || webapp.external_subnet_id != null }
  name                = "pep-${azurerm_linux_web_app.linux_webapps[each.key].name}"
  location            = var.location
  resource_group_name = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name : azurerm_resource_group.app_services_rg[0].name
  subnet_id           = each.value.external_subnet_id != null ? each.value.external_subnet_id : azurerm_subnet.subnets[each.value.subnet_name].id

  private_service_connection {
    name                           = lower("pep-${azurerm_linux_web_app.linux_webapps[each.key].name}")
    private_connection_resource_id = azurerm_linux_web_app.linux_webapps[each.key].id
    is_manual_connection           = false
    subresource_names              = ["sites"]
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }

  # DNS for accessing the website
  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.azurewebsites.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }

  # DNS for deployments
  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.scm.privatelink.azurewebsites.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }
}

# validate across multiple variables
locals {
  subnet_map = { for subnet in var.subnets : subnet.name => subnet.type }

  asp_info = [for plan in var.app_service_plans : {
    sku         = plan.sku_name,
    subnet_type = lookup(local.subnet_map, plan.subnet_name, null)
    }
    if plan.subnet_name != null
  ]

  asp_lists          = jsonencode([for plan in var.app_service_plans : plan.name])
  ec_error_asp       = "            The app service plan does not exist "
  ec_error_asp_valid = "  The valid values are:"

  validate_asp_for_function_apps = [for app in var.function_apps : app.ud_app_service_plan != null ?
    contains([for plan in var.app_service_plans : plan.name], app.ud_app_service_plan) ?
    true : tobool("${local.ec_error_aheader}${local.ec_error_asp}${app.ud_app_service_plan}${local.ec_error_asp_valid}${local.asp_lists} \n ${local.ec_error_zfooter}") :
  tobool("${local.ec_error_aheader}${local.ec_error_asp}${app.ud_app_service_plan}${local.ec_error_asp_valid}${local.asp_lists} \n ${local.ec_error_zfooter}")]

  validate_asp_for_web_apps = [for app in var.web_apps : app.ud_app_service_plan != null ?
    contains([for plan in var.app_service_plans : plan.name], app.ud_app_service_plan) ?
    true : tobool("${local.ec_error_aheader}${local.ec_error_asp}${app.ud_app_service_plan}${local.ec_error_asp_valid}${local.asp_lists} \n ${local.ec_error_zfooter}") :
  tobool("${local.ec_error_aheader}${local.ec_error_asp}${app.ud_app_service_plan}${local.ec_error_asp_valid}${local.asp_lists} \n ${local.ec_error_zfooter}")]

  validate_asp_for_logic_apps = [for app in var.logic_apps : app.ud_app_service_plan != null ?
    contains([for plan in var.app_service_plans : plan.name], app.ud_app_service_plan) ?
    true : tobool("${local.ec_error_aheader}${local.ec_error_asp}${app.ud_app_service_plan}${local.ec_error_asp_valid}${local.asp_lists} \n ${local.ec_error_zfooter}") :
  tobool("${local.ec_error_aheader}${local.ec_error_asp}${app.ud_app_service_plan}${local.ec_error_asp_valid}${local.asp_lists} \n ${local.ec_error_zfooter}")]

  asp_info_with_subnet_type = alltrue([for plan in local.asp_info :
    !contains(["I1", "I2", "I3", "I1v2", "I2v2", "I3v2", "I4v2", "I5v2", "I6v2"], plan.sku) && plan.subnet_type == "app_service_env"
    || contains(["I1", "I2", "I3", "I1v2", "I2v2", "I3v2", "I4v2", "I5v2", "I6v2"], plan.sku) && plan.subnet_type != "app_service_env"
    ? tobool("${local.ec_error_aheader} ${local.ec_error_i_sku_names_app_env_subnets} ${plan.sku}  ${plan.subnet_type} ${local.ec_error_zfooter}") : true
  if plan.subnet_type != null])
}
