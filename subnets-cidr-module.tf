locals {
  
  subnet_list_per_vnet = !local.no_vnet_cidr ? {
    for vnet_cidr_idx, vnet_cidr_el in local.vnet_cidr : "${vnet_cidr_idx}" => {
      vnet_cidr = vnet_cidr_el,
      cidr_module_networks = [
        for subnet in var.subnets : {
          name     = subnet.name,
          new_bits = tonumber(split("/", subnet.cidr_suffix)[1]) - tonumber(split("/", local.vnet_cidr[vnet_cidr_idx])[1])
        } if subnet.cidr_suffix != null && subnet.vnet_cidr_index == vnet_cidr_idx && subnet.extend_vnet == false
      ]
    }
  } : {}

}

module "subnet_addrs" {
  for_each = local.subnet_list_per_vnet
  source   = "hashicorp/subnets/cidr"

  base_cidr_block = each.value.vnet_cidr
  networks        = each.value.cidr_module_networks
}

locals {
  not_null_subnets    = [for subnet in var.subnets : subnet if subnet.name != "null"]
  updated_subnets     = local.no_vnet_cidr ? [] : [for subnet in local.not_null_subnets : merge(subnet, { cidr = ["${module.subnet_addrs["${subnet.vnet_cidr_index}"].network_cidr_blocks["${subnet.name}"]}"] }) if contains(keys(module.subnet_addrs["${subnet.vnet_cidr_index}"].network_cidr_blocks), subnet.name)]
  not_updated_subnets = local.no_vnet_cidr ? [] : [for subnet in local.not_null_subnets : subnet if !contains(keys(module.subnet_addrs["${subnet.vnet_cidr_index}"].network_cidr_blocks), subnet.name)]
  defined_subnets     = local.no_vnet_cidr ? var.subnets : concat(local.updated_subnets, local.not_updated_subnets)
  auto_pe_subnet = (local.no_vnet_cidr && var.is_spoke && length(var.subnets) > 0 && local.build_base_resources) || (var.is_spoke && var.is_host) ? [{
    name                                  = "managed_pe"
    cidr                                  = []
    cidr_suffix                           = "/29"
    type                                  = "pe"
    egress_type                           = "azure_firewall"
    vnet_cidr_index                       = 0
    routes                                = []
    delegation_type                       = null
    disable_bgp_route_propagation         = false
    private_endpoints                     = []
    delegations                           = []
    allow_internal_https_traffic_inbound  = false
    allow_internal_https_traffic_outbound = false
    nsg_rulesets                          = []
    service_endpoints                     = []
    extend_vnet                           = false
  }] : []
  all_subnets    = concat(local.defined_subnets, local.auto_pe_subnet)
  pe_subnet      = [for subnet in local.all_subnets : subnet.name if subnet.type == "pe"]
  pe_subnet_name = length(local.pe_subnet) > 0 ? local.pe_subnet[0] : null
}