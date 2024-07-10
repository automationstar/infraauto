locals {
  nva_ip_addresses = {
    eastus2   = "10.155.62.4"
    centralus = "10.155.190.4"
    westus3   = "10.155.62.4"  # THIS IS WRONG
    eastus    = "10.155.190.4" # THIS IS WRONG
  }

  azfw_ip_addresses = {
    eastus2_prod      = "10.155.8.4"
    eastus2_nonprod   = "10.229.1.4" 
    centralus_prod    = "10.155.136.4"
    centralus_nonprod = "10.229.129.4"
    westus3_prod      = "10.74.129.4"
    westus3_nonprod   = "10.207.129.4"
    eastus_prod       = "10.74.1.4"
    eastus_nonprod    = "10.207.1.4" 
  }

  gateway_route_tables = {
    eastus2_nonprod = "rt-corp-hub-nonprod-use2-GatewaySubnet"
    centralus_nonprod = "rt-corp-hub-nonprod-usc-GatewaySubnet"
    eastus_prod = "rt-corp-hub-prod-use-gateway"
    eastus_nonprod = "rt-corp-hub-nonprod-use-GatewaySubnet"
    westus3_prod = "rt-corp-hub-prod-usw3-GatewaySubnet"
    westus3_nonprod = "rt-corp-hub-nonprod-usw3-GatewaySubnet"
    
    eastus2_prod = ""
    centralus_prod = ""
  }

  firewall_routes = { for subnet in local.all_subnets : subnet.name => {
    route_table_key        = "${subnet.name}"
    route_name             = "NVAEgress",
    address_prefix         = "0.0.0.0/0",
    next_hop_type          = "VirtualAppliance",
    next_hop_in_ip_address = "${local.nva_ip_addresses["${var.location}"]}"
  } if subnet.egress_type == "cisco_firewall" && !contains(["gateway","firewall"], subnet.type) }

  azfw_routes = { for subnet in local.all_subnets : subnet.name => {
    route_table_key        = "${subnet.name}"
    route_name             = var.is_hub ? "default" : "AKS_AzFwEgress",
    address_prefix         = "0.0.0.0/0",
    next_hop_type          = "VirtualAppliance",
    next_hop_in_ip_address = "${local.azfw_ip_addresses["${local.region_environment}"]}"
  } if subnet.type != "firewall" && subnet.type != "gateway" && subnet.egress_type == "azure_firewall" || subnet.egress_type == "aks" || (subnet.type == "aks" && subnet.egress_type != "cisco_firewall") }

  pci_routes = { for subnet in local.all_subnets : subnet.name => {
    route_table_key        = "${subnet.name}"
    route_name             = "NVAEgress",
    address_prefix         = "0.0.0.0/0",
    next_hop_type          = "VirtualAppliance",
    next_hop_in_ip_address = "10.155.187.4" # PCI Firewall
  } if subnet.egress_type == "pci" }

  
  apim_routes = [
    {
      route_name     = "apim-mgmt",
      address_prefix = "ApiManagement",
      next_hop_type  = "Internet",
    },
    {
      route_name     = "apim-monitor",
      address_prefix = "AzureMonitor",
      next_hop_type  = "Internet",
    },
    {
      route_name     = "apim-sql",
      address_prefix = "Sql",
      next_hop_type  = "Internet",
    }
  ]

  apim_subnet_routes = {
    for route in flatten([
      for subnet in local.all_subnets : [
        for route in local.apim_routes : merge(route, { route_table_key : subnet.name })
      ] if subnet.type == "apim"
    ]) : "${route.route_table_key}_${route.route_name}" => route
  }

  databricks_routes = [
    {
      route_name     = "adb-eventhub",
      address_prefix = "EventHub.${var.location}",
      next_hop_type  = "Internet",
    },
    {
      route_name     = "adb-storage",
      address_prefix = "Storage.${var.location}",
      next_hop_type  = "Internet",
    },
    {
      route_name     = "adb-metastore",
      address_prefix = "Sql.${var.location}",
      next_hop_type  = "Internet",
    },
    {
      route_name     = "adb-extinfra",
      address_prefix = "13.91.84.96/28",
      next_hop_type  = "Internet",
    },
    {
      route_name     = "adb-servicetag",
      address_prefix = "AzureDatabricks",
      next_hop_type  = "Internet",
    }
  ]

  databricks_subnet_routes = {
    for route in flatten([
      for subnet in local.all_subnets : [
        for route in local.databricks_routes : merge(route, { route_table_key : subnet.name })
      ] if subnet.type == "databricks"
    ]) : "${route.route_table_key}_${route.route_name}" => route
  }

  other_routes = {
    for route in flatten([
      for subnet in local.all_subnets : [
        for route in subnet.routes : merge(route, { route_table_key : subnet.name })
      ] if subnet.routes != null && subnet.type != "firewall"
    ]) : "${route.route_table_key}_${route.route_name}" => route
  }

  all_routes = merge(local.firewall_routes, local.azfw_routes, local.pci_routes, local.apim_subnet_routes, local.databricks_subnet_routes, local.other_routes)
}

data "azurerm_route_table" "hub_gateway_route_table" {
  provider = azurerm.hub
  count = local.routing_strategy == "static" && !local.is_client && !var.is_hub && !local.uses_legacy_hub ? 1 : 0
  name = local.gateway_route_tables[local.region_environment]
  resource_group_name = local.hub_vnet_rg_map[local.region_environment]
}

locals {
  all_vnet_cidrs = concat(local.vnet_cidrs, var.vnet_cidr )
}

resource "azurerm_route" "hub_gateway_route" {
  provider = azurerm.hub
  for_each = local.routing_strategy == "static" && !var.is_hub && !local.is_client ? {for index,vnet in local.all_vnet_cidrs : index => vnet } : {}
  name = "gateway-to-${local.vnet_name}-${each.key}"
  resource_group_name = local.hub_vnet_rg_map[local.region_environment]
  route_table_name = data.azurerm_route_table.hub_gateway_route_table[0].name
  address_prefix         = azurerm_virtual_network.vnet[0].address_space[each.key]
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = local.azfw_ip_addresses[local.region_environment]
}

resource "azurerm_route_table" "route_tables" {
  for_each                      = { for subnet in local.all_subnets : subnet.name => subnet }
  name                          = "rt-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.value.name}"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.network_rg[0].name
  disable_bgp_route_propagation = each.value.egress_type == "pci" ? true : local.uses_legacy_hub || each.value.type == "gateway" || var.allow_bgp ? each.value.disable_bgp_route_propagation : true

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}


resource "azurerm_subnet_route_table_association" "route_table_subnet_association" {
  for_each       = { for subnet in local.all_subnets : subnet.name => subnet if !contains(["firewall"], subnet.type) }
  route_table_id = azurerm_route_table.route_tables[each.value.name].id
  subnet_id      = azurerm_subnet.subnets[each.value.name].id
}

resource "azurerm_route" "routes" {
  for_each               = local.all_routes
  name                   = "udr-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.value.route_name}"
  resource_group_name    = azurerm_resource_group.network_rg[0].name
  route_table_name       = azurerm_route_table.route_tables[each.value.route_table_key].name
  address_prefix         = each.value.address_prefix
  next_hop_type          = each.value.next_hop_type
  next_hop_in_ip_address = lookup(each.value, "next_hop_in_ip_address", null)
}

## 
