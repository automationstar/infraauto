data "azurerm_network_watcher" "network_watcher" {
  name                = "NetworkWatcher_${var.location}"
  resource_group_name = "NetworkWatcherRG"

  depends_on = [azurerm_virtual_network.vnet[0]]
}


locals {
  shglobalntwkflowlogs_map = {
    "eastus2_prod" = {
      storage_account_id    = "/subscriptions/59b2cd00-9406-4a41-a772-e073dbe19796/resourceGroups/RG-cvsnsgflhub000/providers/Microsoft.Storage/storageAccounts/sacvsnsgflhub000"
      workspace_id          = "7558b9a5-d70f-45e7-8156-69aa9360fb61"
      workspace_resource_id = "/subscriptions/59b2cd00-9406-4a41-a772-e073dbe19796/resourceGroups/rg-securehub-global-network-watcher-flow-logs-use2/providers/Microsoft.OperationalInsights/workspaces/log-securehub-global-ntwk-flowlogs-use2"
    },
    "eastus2_nonprod" = {
      storage_account_id    = "/subscriptions/59b2cd00-9406-4a41-a772-e073dbe19796/resourceGroups/RG-cvsnsgflhub000/providers/Microsoft.Storage/storageAccounts/sacvsnsgflhub000" #NEEDS UPDATE
      workspace_id          = "2a777052-95be-4eb4-b8b0-3f41589f4eed"
      workspace_resource_id = "/subscriptions/a5051462-84f2-4236-8e09-dc4b685e95af/resourceGroups/rg-corp-hub-nonprod-use2-secr/providers/Microsoft.OperationalInsights/workspaces/log-corp-hub-nonprod-use2"
    }
    "centralus_prod" = {
      storage_account_id    = "/subscriptions/29ea5d6f-8539-4a95-8198-ca801994cbdb/resourceGroups/RG-cvsnsgflhub000/providers/Microsoft.Storage/storageAccounts/sacvsnsgflhubusc000"
      workspace_id          = "fa1e8ded-4b28-40a8-bdec-d000f55fbeb6"
      workspace_resource_id = "/subscriptions/29ea5d6f-8539-4a95-8198-ca801994cbdb/resourceGroups/rg-securehub-global-network-watcher-flow-logs-usc/providers/Microsoft.OperationalInsights/workspaces/log-securehub-global-ntwk-flowlogs-usc"
    },
    "centralus_nonprod" = {
      storage_account_id    = "/subscriptions/29ea5d6f-8539-4a95-8198-ca801994cbdb/resourceGroups/RG-cvsnsgflhub000/providers/Microsoft.Storage/storageAccounts/sacvsnsgflhubusc000" #NEEDS UPDATE
      workspace_id          = "2a777052-95be-4eb4-b8b0-3f41589f4eed"
      workspace_resource_id = "/subscriptions/29ea5d6f-8539-4a95-8198-ca801994cbdb/resourceGroups/rg-securehub-global-network-watcher-flow-logs-usc/providers/Microsoft.OperationalInsights/workspaces/log-securehub-global-ntwk-flowlogs-usc"
    },
    "westus3_prod" = {
      storage_account_id    = "/subscriptions/0b379ff1-4fa8-48c7-b2ed-c85c4d91c29f/resourceGroups/rg-corp-hub-prod-usw3-log/providers/Microsoft.Storage/storageAccounts/stcorphub0703nwfl"
      workspace_id          = "c87c76f3-20c8-4f36-b119-e0eac428ac9b"
      workspace_resource_id = "/subscriptions/0b379ff1-4fa8-48c7-b2ed-c85c4d91c29f/resourceGroups/rg-corp-hub-prod-usw3-secr/providers/Microsoft.OperationalInsights/workspaces/log-corp-hub-prod-usw3"
    },
    "westus3_nonprod" = { #NEEDS UPDATE
      storage_account_id    = "/subscriptions/0b379ff1-4fa8-48c7-b2ed-c85c4d91c29f/resourceGroups/rg-corp-hub-prod-usw3-log/providers/Microsoft.Storage/storageAccounts/stcorphub0703nwfl"
      workspace_id          = "c87c76f3-20c8-4f36-b119-e0eac428ac9b"
      workspace_resource_id = "/subscriptions/0b379ff1-4fa8-48c7-b2ed-c85c4d91c29f/resourceGroups/rg-corp-hub-prod-usw3-secr/providers/Microsoft.OperationalInsights/workspaces/log-corp-hub-prod-usw3"
    },
    "eastus_prod" = {
      storage_account_id    = "/subscriptions/f57af375-a161-490e-956c-f75815022949/resourceGroups/rg-corp-hub-prod-use-log/providers/Microsoft.Storage/storageAccounts/stcorphub0704nwfl"
      workspace_id          = "6b2fafbd-a9c0-41c7-afb0-29be50e36143"
      workspace_resource_id = "/subscriptions/f57af375-a161-490e-956c-f75815022949/resourceGroups/rg-corp-hub-prod-use-secr/providers/Microsoft.OperationalInsights/workspaces/log-corp-hub-prod-use"
    },
    "eastus_nonprod" = { #NEEDS UPDATE
      storage_account_id    = "/subscriptions/f57af375-a161-490e-956c-f75815022949/resourceGroups/rg-corp-hub-prod-use-log/providers/Microsoft.Storage/storageAccounts/stcorphub0704nwfl"
      workspace_id          = "6b2fafbd-a9c0-41c7-afb0-29be50e36143"
      workspace_resource_id = "/subscriptions/f57af375-a161-490e-956c-f75815022949/resourceGroups/rg-corp-hub-prod-use-secr/providers/Microsoft.OperationalInsights/workspaces/log-corp-hub-prod-use"
    },
  }
}

resource "azurerm_network_watcher_flow_log" "main" {
  count = length(local.all_subnets) > 0 && var.is_peered && !var.disable_watcher || var.is_hub  ? 1 : 0

  network_watcher_name = data.azurerm_network_watcher.network_watcher.name
  resource_group_name  = "NetworkWatcherRG"
  name                 = "nwfl-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}"
  location             = var.location

  network_security_group_id = azurerm_network_security_group.network_security_group[0].id
  storage_account_id        = local.shglobalntwkflowlogs_map[local.region_environment].storage_account_id
  enabled                   = true
  version                   = 2

  retention_policy {
    enabled = true
    days    = var.flowlog_retention_days
  }

  dynamic "traffic_analytics" {
    for_each = var.use_ud_law_fl ? (var.log_analytics_workspace != "none" ? [
      {
        workspace_id          = azurerm_log_analytics_workspace.log_analytics_workspace[0].workspace_id,
        workspace_resource_id = azurerm_log_analytics_workspace.log_analytics_workspace[0].id
      }
      ] : []) : (var.use_global_law_fl ? [
      {
        workspace_id          = local.shglobalntwkflowlogs_map[local.region_environment].workspace_id
        workspace_resource_id = local.shglobalntwkflowlogs_map[local.region_environment].workspace_resource_id
      }
    ] : [])
    content {
      enabled               = true
      workspace_id          = traffic_analytics.value.workspace_id
      workspace_region      = var.location
      workspace_resource_id = traffic_analytics.value.workspace_resource_id
      interval_in_minutes   = 10
    }
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}
