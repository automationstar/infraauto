locals {
  pes = {
    for pe in flatten([
      for subnet in local.all_subnets : [
        for pe in subnet.private_endpoints : merge(pe, { subnet_name : subnet.name })
      ] if subnet.private_endpoints != null
    ]) : "${pe.subnet_name}_${pe.resource_name}" => pe
  }

  external_pes = {
    for pe in var.external_private_endpoints : "external-${pe.name}" => pe
  }
}

data "azurerm_resources" "pe_resources" {
  for_each            = local.pes
  name                = each.value.resource_name
  resource_group_name = each.value.resource_group_name
}

data "azurerm_resources" "external_pe_resources" {
  for_each            = local.external_pes
  name                = each.value.resource_name
  resource_group_name = each.value.resource_group_name
}
locals {
  validate_external_resource_exists = [for pe_resource in local.external_pes : length(data.azurerm_resources.external_pe_resources["external-${pe_resource.name}"].resources) != 0 ?
  true : tobool("${local.ec_error_aheader}${local.ec_error_not_exist} ${local.ec_error_zfooter}")]
}
locals {
  # multi_subresource_default_map references:
  #  - https://registry.terraform.io/providers/hashicorp/azurerm/3.21.0/docs/resources/private_endpoint#subresource_names
  #  - https://docs.microsoft.com/en-us/azure/private-link/private-endpoint-overview#private-link-resource
  #  - CosmosDB's resource type seems to differ from the table above: https://docs.microsoft.com/en-us/azure/templates/microsoft.documentdb/allversions#resource-types-and-versions
  multi_subresource_default_map = {
    "Microsoft.Appconfiguration/configurationStores" = ["configurationStores"]
    # "Microsoft.AzureCosmosDB/databaseAccounts"       = ["sql"]
    "Microsoft.DocumentDb/databaseAccounts"      = ["sql"]
    "Microsoft.Cache/Redis"                      = ["redisCache"]
    "Microsoft.CognitiveServices/accounts"       = ["account"]
    "Microsoft.Cache/redisEnterprise"            = ["redisEnterprise"]
    "Microsoft.Compute/diskAccesses"             = ["managed disk"]
    "Microsoft.ContainerRegistry/registries"     = ["registry"]
    "Microsoft.ContainerService/managedClusters" = ["management"]
    "Microsoft.DataFactory/factories"            = ["dataFactory"]
    "Microsoft.Kusto/clusters"                   = ["cluster"]
    "Microsoft.DBforMariaDB/servers"             = ["mariadbServer"]
    "Microsoft.DBforMySQL/servers"               = ["mysqlServer"]
    "Microsoft.DBforPostgreSQL/servers"          = ["postgresqlServer"]
    "Microsoft.EventGrid/domains"                = ["domain"]
    "Microsoft.EventGrid/topics"                 = ["topic"]
    "Microsoft.EventHub/namespaces"              = ["namespace"]
    "Microsoft.HDInsight/clusters"               = ["cluster"]
    "Microsoft.KeyVault/vaults"                  = ["vault"]
    "Microsoft.Network/applicationgateways"      = ["application gateway"]
    "Microsoft.RecoveryServices/vaults"          = ["AzureBackup", "AzureSiteRecovery"]
    "Microsoft.ServiceBus/namespaces"            = ["namespace"]
    "Microsoft.Storage/storageAccounts"          = ["blob"]
    "Microsoft.Sql/servers"                      = ["sqlServer"]
    "Microsoft.Web/hostingEnvironments"          = ["hosting environment"]
    "Microsoft.Web/sites"                        = ["sites"]
    "Microsoft.Web/staticSites"                  = ["staticSites"]
  }

  pe_list_rtype = [for pe_key, pe in local.pes : merge(pe, {
    resource_type = data.azurerm_resources.pe_resources["${pe_key}"].resources[0].type
  })]

  pe_list_subresources = [for pe_key, pe in local.pe_list_rtype : merge(pe, {
    subresource_names = pe.subresource_names != null ? pe.subresource_names : local.multi_subresource_default_map["${pe.resource_type}"]
  })]

  pe_list = [for pe_key, pe in local.pe_list_subresources : merge(pe, {
    pe_name = pe.name != null ? pe.name : lower(replace(pe.subresource_names[0], " ", ""))
  })]

  external_pe_list_rtype = [for pe_key, pe in local.external_pes : merge(pe, {
    resource_type = data.azurerm_resources.external_pe_resources["${pe_key}"].resources[0].type
  })]

  external_pe_list_subresources = [for pe_key, pe in local.external_pe_list_rtype : merge(pe, {
    subresource_names = local.multi_subresource_default_map["${pe.resource_type}"]
  })]

  private_dns_zones = {
    privatelink-postgres-database-azure-com = "privatelink.postgres.database.azure.com"
  }
}

resource "azurerm_private_dns_zone" "private_dns_zones" {
  for_each            = { for zone, url in local.private_dns_zones : zone => url if(length(var.psqls) > 0 && !local.is_client) || var.is_host }
  name                = each.value
  resource_group_name = azurerm_resource_group.network_rg[0].name

  tags = local.dns_zone_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "private_dns_network_links" {
  depends_on = [azurerm_private_dns_zone.private_dns_zones]

  for_each              = { for zone, url in local.private_dns_zones : zone => url if(length(var.psqls) > 0 && !local.is_client) || var.is_host }
  name                  = "${local.vnet_name}-link"
  resource_group_name   = azurerm_resource_group.network_rg[0].name
  private_dns_zone_name = each.value
  virtual_network_id    = local.vnet_id

  tags = local.dns_zone_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }

}


resource "azurerm_private_endpoint" "pes" {
  for_each            = { for pe in local.pe_list : "${pe.subnet_name}_${pe.resource_name}" => pe }
  name                = "pe-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.value.pe_name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.network_rg[0].name
  subnet_id           = azurerm_subnet.subnets[each.value.subnet_name].id

  private_service_connection {
    name                           = "${each.value.pe_name}-privateserviceconnection"
    private_connection_resource_id = data.azurerm_resources.pe_resources["${each.key}"].resources[0].id
    is_manual_connection           = false
    subresource_names              = each.value.subresource_names
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  depends_on = [azurerm_key_vault_key.base_kv_key]
}

resource "azurerm_private_endpoint" "external_pes" {
  for_each            = { for pe in local.external_pe_list_subresources : "external-${pe.name}" => pe if var.is_spoke == false && var.is_peered == false }
  location            = var.location
  name                = "pe-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.value.name}"
  resource_group_name = each.value.resource_group_name
  subnet_id           = each.value.subnet_id

  private_service_connection {
    name                           = "${each.value.name}-privateserviceconnection"
    private_connection_resource_id = data.azurerm_resources.external_pe_resources["${each.key}"].resources[0].id
    is_manual_connection           = false
    subresource_names              = each.value.subresource_names
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

