resource "azurerm_application_insights" "app_insights" {
  for_each = { for app_insight in var.app_insights : app_insight.name => app_insight }

  name                = "appi-${var.line_of_business}${var.application_id}${local.env_region}${each.key}"
  resource_group_name = azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].name
  location            = azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].location
  workspace_id        = var.log_analytics_workspace != "none" ? azurerm_log_analytics_workspace.log_analytics_workspace[0].id : null
  application_type    = each.value.application_type

  daily_data_cap_in_gb = each.value.daily_data_cap_in_gb
  retention_in_days    = each.value.retention_in_days

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_monitor_diagnostic_setting" "diag_app_insights" {
  for_each = { for app_insight in var.app_insights : app_insight.name => app_insight }

  name                           = "diag-${azurerm_application_insights.app_insights[each.key].name}"
  target_resource_id             = azurerm_application_insights.app_insights[each.key].id
  log_analytics_workspace_id     = var.log_analytics_workspace != "none" ? azurerm_log_analytics_workspace.log_analytics_workspace[0].id : null
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
  lifecycle {
    ignore_changes = [metric]
  }
}