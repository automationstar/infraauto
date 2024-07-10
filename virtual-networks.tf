locals {
  dns_servers = {
    eastus2   = ["10.155.40.7", "10.155.40.8"]
    centralus = ["10.155.168.7", "10.155.168.8"]
    eastus   = ["10.155.40.7", "10.155.40.8"]
    westus3 = ["10.155.40.7", "10.155.40.8"]
    # eastus and westus3 use eastus2's DNS servers until they get their own
  }
  all_dns_servers = concat(var.additional_dns_servers, local.dns_servers["${var.location}"])

  bgp_community = {
    eastus2   = "12076:20010"
    centralus = "12076:20110"
    eastus    = "12076:20010"
    westus3   = "12076:20210"
  }
}

locals {
  vnet_cidr = (length(local.vnet_cidrs) > 0 ?
    [for vnet in local.vnet_cidrs :
      local.network_strategy == "shared_vnet" && !var.is_host ? data.infoblox_ipv4_network_container.host_vnet_container[vnet.index].cidr : infoblox_ipv4_network_container.vnet_container[vnet.index].cidr
    ]
    : length(var.vnet_cidr) > 0 ?
    concat(var.vnet_cidr, [for request in infoblox_ipv4_network.vnet_cidr_list : request.cidr])
    : local.no_vnet_cidr ? [for request in infoblox_ipv4_network.vnet_cidr_list : request.cidr]
    : concat(var.vnet_cidr, [for request in infoblox_ipv4_network.vnet_cidr_list : request.cidr])
  )

  host_vnet_name    = lower("vnet-${local.host_name_prefix}-host${var.host_index}")
  host_vnet_rg_name = lower("rg-${local.host_name_prefix}-ntwk${var.host_index != 0 ? var.host_index : ""}")
  host_vnet_id      = local.is_client ? data.azurerm_virtual_network.host_vnet[0].id : null

  network_strategy = var.internal_use.network_strategy
}

data "azurerm_virtual_network" "host_vnet" {
  count = local.is_client ? 1 : 0

  name                = local.host_vnet_name
  resource_group_name = local.host_vnet_rg_name

}


resource "azurerm_virtual_network" "vnet" {
  count = (length(local.vnet_cidr) > 0 && local.network_strategy == "classic") || var.is_host ? 1 : 0

  name                = local.vnet_name
  resource_group_name = azurerm_resource_group.network_rg[0].name
  address_space       = local.vnet_cidr
  location            = var.location
  dns_servers         = local.all_dns_servers
  bgp_community       = local.uses_legacy_hub ? null : local.bgp_community[var.location]

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}
