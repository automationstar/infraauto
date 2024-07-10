locals {
  delegation_map = {
    app_service_env = {
      delegation_key = {
        delegation_name            = "Microsoft.Web.hostingEnvironments"
        service_delegation_name    = "Microsoft.Web/hostingEnvironments"
        service_delegation_actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
    }
    app_service_farm = {
      delegation_key = {
        delegation_name            = "Microsoft.Web.serverFarms"
        service_delegation_name    = "Microsoft.Web/serverFarms"
        service_delegation_actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
    }
    databricks = {
      delegation_key = {
        delegation_name            = "Microsoft.Databricks/workspaces"
        service_delegation_name    = "Microsoft.Databricks/workspaces"
        service_delegation_actions = ["Microsoft.Network/virtualNetworks/subnets/join/action", "Microsoft.Network/virtualNetworks/subnets/prepareNetworkPolicies/action", "Microsoft.Network/virtualNetworks/subnets/unprepareNetworkPolicies/action", ]
      }
    }
  }

  db_delegation_map = {
    for key, db_subnet in local.db_delegated_subnets_list : db_subnet.type => {
      delegation_key = db_subnet.delegation_key
    }
  }

  delegation_map_all = merge(local.delegation_map, local.db_delegation_map)

  all_subnets_configured = { for subnet in local.all_subnets : subnet.name => (subnet.delegation_type != null) ? subnet : merge(subnet, { delegation_type = subnet.type }) }

  subnets_with_delegation_info = { for subnet in local.all_subnets_configured : subnet.name => merge(subnet, {
    delegation = merge((subnet.delegations != null) ? { for delegation in subnet.delegations : delegation.delegation_name => delegation } : {}, lookup(local.delegation_map_all, subnet.delegation_type, {}))
  }) }

  subnet_with_infoblox_v1 = (
    local.no_vnet_cidr && local.ipam_version == 1 ?
    { for subnet in local.subnets_with_delegation_info :
      subnet.name => merge(subnet, { cidr = ["${infoblox_ipv4_network.vnet_cidr_list[subnet.name].cidr}"] })
    }
    :
    { for subnet in local.subnets_with_delegation_info :
      subnet.name => subnet.extend_vnet ? merge(subnet, { cidr = ["${infoblox_ipv4_network.vnet_cidr_list[subnet.name].cidr}"] })
      : subnet
    }
  )

  subnet_with_infoblox_v2 = (
    local.no_vnet_cidr && local.ipam_version == 2 ?
    { for subnet in local.subnets_with_delegation_info :
      subnet.name => contains(local.subnets_consuming_full_vnet, subnet.name) ?
      merge(subnet, { cidr = ["${infoblox_ipv4_network_container.vnet_container[subnet.vnet_cidr_index].cidr}"] })
      : merge(subnet, { cidr = ["${infoblox_ipv4_network.subnet_cidr_list[subnet.name].cidr}"] })
    }
    : { for subnet in local.subnets_with_delegation_info : subnet.name => subnet }
  )

  subnet_with_infoblox = local.ipam_version == 2 ? local.subnet_with_infoblox_v2 : local.subnet_with_infoblox_v1
}

resource "azurerm_subnet" "subnets" {
  depends_on = [local.peering_resources]
  for_each   = local.subnet_with_infoblox

  name                 = each.value.type == "gateway" ? "GatewaySubnet" : each.value.type == "firewall" ? "AzureFirewallSubnet" : "snet-${local.name_prefix}-${each.value.name}"
  resource_group_name  = local.vnet_rg_name
  virtual_network_name = local.vnet_name
  address_prefixes     = each.value.cidr
  service_endpoints = distinct(concat(coalesce(each.value.service_endpoints, []),
    lookup({
      "cog"  = ["Microsoft.CognitiveServices"],
      "apim" = ["Microsoft.KeyVault", "Microsoft.Sql", "Microsoft.Storage", "Microsoft.EventHub", "Microsoft.AzureActiveDirectory", "Microsoft.ServiceBus"]
    }, each.value.type, []))
  )
  private_endpoint_network_policies_enabled = local.uses_legacy_hub ? false : true

  dynamic "delegation" {
    for_each = each.value.delegation

    content {
      name = delegation.value.delegation_name
      service_delegation {
        name    = delegation.value.service_delegation_name
        actions = delegation.value.service_delegation_actions
      }
    }
  }

  lifecycle {
    ignore_changes = [
      name
    ]
  }
}
