resource "azurerm_log_analytics_workspace" "log_analytics_workspace" {
  count                      = var.log_analytics_workspace != "none" ? 1 : 0
  name                       = "log-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}"
  location                   = var.location
  resource_group_name        = var.log_analytics_workspace_specs.ud_resource_group != "none" ? azurerm_resource_group.ud_rgs[var.log_analytics_workspace_specs.ud_resource_group].name : azurerm_resource_group.secr_rg[0].name
  sku                        = var.log_analytics_workspace_specs.sku
  retention_in_days          = var.log_analytics_workspace_specs.retention_in_days
  internet_ingestion_enabled = true
  internet_query_enabled     = true

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Get Subscription Data
data "azurerm_subscription" "current" {
}

resource "azurerm_monitor_diagnostic_setting" "subscription_diagnostics" {
  count                      = var.enable_subscription_diagnostics && var.log_analytics_workspace != "none" ? 1 : 0
  name                       = "${data.azurerm_subscription.current.display_name}_diagnostics_ec"
  target_resource_id         = data.azurerm_subscription.current.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.log_analytics_workspace[0].id


  dynamic "enabled_log" {
    for_each = toset(var.subscription_diagnostic_objects.log)

    content {
      category = enabled_log.value[0]
    }
  }

  dynamic "metric" {
    for_each = toset(var.subscription_diagnostic_objects.metric)

    content {
      category = metric.value[0]
      enabled  = metric.value[1]

      retention_policy {
        enabled = metric.value[2]
        days    = metric.value[3]
      }
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "law_diagnostics_eventhub" {
  count = var.log_analytics_workspace != "none" && var.forward_law_to_eh  && !var.is_hub ? 1 : 0

  name                           = "diag-${azurerm_log_analytics_workspace.log_analytics_workspace[count.index].name}"
  target_resource_id             = azurerm_log_analytics_workspace.log_analytics_workspace[count.index].id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  storage_account_id             = var.diag_storage_account_id
  partner_solution_id            = var.partner_solution_id
  eventhub_authorization_rule_id = local.eventhub_info[local.region_environment].eventhub_authorization_rule_id
  eventhub_name                  = local.eventhub_info[local.region_environment].eventhub_name

  # this enables the Audit Logging on the LAW
  enabled_log {
    category_group = "audit"

    retention_policy {
      enabled = false
    }
  }

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
