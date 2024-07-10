resource "azurerm_search_service" "srchs" {
  for_each = { for srch_info in var.search_services : srch_info.name => srch_info if srch_info.deploy_mode == "azurerm" }

  name                = "srch-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.value.name}"
  resource_group_name = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].name : azurerm_resource_group.srch_rg[0].name
  location            = var.location
  sku                 = each.value.sku_name

  local_authentication_enabled             = false
  public_network_access_enabled            = false
  partition_count                          = each.value.partition_count
  replica_count                            = each.value.replica_count
  customer_managed_key_enforcement_enabled = true

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  identity {
    type = "SystemAssigned"
  }
}

resource "azapi_resource" "api_srch" {
  for_each                  = { for srch_info in var.search_services : srch_info.name => srch_info if srch_info.deploy_mode == "api" }
  provider                  = azapi.azapi
  schema_validation_enabled = false
  type                      = "Microsoft.Search/searchServices@2022-09-01"

  name      = "srch-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.value.name}"
  location  = var.location
  parent_id = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].id : azurerm_resource_group.srch_rg[0].id
  identity {
    type = "SystemAssigned"
  }
  body = jsonencode({
    properties = {
      # authOptions can't be set if localauth is disabled

      # authOptions = {
      #   aadOrApiKey = {
      #     aadAuthFailureMode = "http403"
      #   }
      # }
      disableLocalAuth = each.value.disable_local_auth
      encryptionWithCmk = {
        enforcement                = "Enabled"
        encryptionComplianceStatus = "Compliant" #forces AzAPI use per MS
      }
      hostingMode         = "default"
      partitionCount      = tonumber(each.value.partition_count)
      publicNetworkAccess = "Disabled"
      replicaCount        = tonumber(each.value.replica_count)
    }
    sku = {
      name = each.value.sku_name
    }
    tags = local.all_tags
  })
}


resource "azurerm_private_endpoint" "srch_pes" {
  for_each            = { for srch_info in var.search_services : srch_info.name => srch_info }
  name                = "pe-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.value.name}"
  location            = var.location
  resource_group_name = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].name : azurerm_resource_group.srch_rg[0].name
  subnet_id           = each.value.external_subnet_id != null ? each.value.external_subnet_id : azurerm_subnet.subnets["${each.value.subnet_name}"].id

  private_service_connection {
    name                           = "${each.value.name}-privateserviceconnection"
    private_connection_resource_id = each.value.deploy_mode == "api" ? azapi_resource.api_srch[each.value.name].id : azurerm_search_service.srchs["${each.value.name}"].id
    is_manual_connection           = false
    subresource_names              = ["searchService"]
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
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.search.windows.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }
}