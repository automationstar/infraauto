locals {
  network_view = "Lab"

  net_containers = {
    "prod_use2"    = ["10.83.0.0/18", "10.85.0.0/18"]
    "nonprod_use2" = ["10.83.64.0/18", "10.85.64.0/18", "10.229.32.0/19","10.229.64.0/18"]
    "prod_usc"     = ["10.83.128.0/18", "10.85.128.0/18"]
    "nonprod_usc"  = ["10.83.192.0/18", "10.85.192.0/18", "10.229.160.0/19","10.229.192.0/18"]
    "prod_usw3"    = ["10.74.160.0/19", "10.74.144.0/20"]
    "nonprod_usw3" = ["10.207.128.0/17"]
    "prod_use"     = ["10.74.32.0/19", "10.74.16.0/20"]
    "nonprod_use"  = ["10.207.0.0/17"]
  }

  cidr_map = {
    "/29" = 8
    "/28" = 16
    "/27" = 32
    "/26" = 64
    "/25" = 128
    "/24" = 256
    "/23" = 512
    "/22" = 1024
    "/21" = 2048
    "/20" = 4096
    "/19" = 8192
    "/18" = 16384
    # Larger shouldn't be allowed?
  }

  no_vnet_cidr               = length(var.vnet_cidr) == 0
  ipam_version               = var.internal_use.ipam_version
  all_subnets_for_vnet_cidrs = concat(var.subnets, local.auto_pe_subnet)
  ## Add subnet cidrs together to find nearest vnet cidr

  # create a set of all the vnet indexes that exist in the spoke file 
  vnet_indices = (local.no_vnet_cidr && local.ipam_version == 2 ?
    tolist(toset([for subnet in local.all_subnets_for_vnet_cidrs : subnet.vnet_cidr_index]))
  : [])

  vnet_cidr_suffixes = [for idx, suffix in var.vnet_cidr_suffixes : idx]

  # create a list of the sum of how many IPs are needed for each vnet address block (index)
  subnet_cidr_total = (length(local.vnet_cidr_suffixes) > 0 ?
    [for idx in local.vnet_cidr_suffixes :
    lookup(local.cidr_map, var.vnet_cidr_suffixes[idx], 0)] :
    length(local.vnet_indices) > 0 && local.ipam_version == 2 ?
    [for index in local.vnet_indices :
      sum([for subnet in local.all_subnets_for_vnet_cidrs :
      lookup(local.cidr_map, subnet.cidr_suffix, 0) if subnet.vnet_cidr_index == index])
    ] :
  null)

  # for each vnet address block, Create a list of all the suffixes that are equal to or bigger then the required number of ips from the step above
  larger_ip_suffixes = (local.subnet_cidr_total != null ?
    [for cidr_total in local.subnet_cidr_total :
      [for suffix, value in local.cidr_map :
      suffix if value >= cidr_total]
    ] :
  null)

  # for each vnet address block, identify the smallest block from the options identified in the step above
  closest_cidr_suffix = (local.larger_ip_suffixes != null ?
    [for suffix in local.larger_ip_suffixes :
      reverse(sort(suffix))[0]
    ] :
  null)


  # generate a map out of the lists created above
  vnet_cidrs_no_names = [for idx in local.vnet_indices : {
    index        = idx
    cidr_suffix  = length(var.vnet_cidr_suffixes) > 0 ? split("/", var.vnet_cidr_suffixes[idx])[1] : split("/", local.closest_cidr_suffix[idx])[1]
    subnet_total = local.subnet_cidr_total[idx]
    is_one_subnet = length(local.vnet_cidr_suffixes) == 0 && local.closest_cidr_suffix != null && !local.is_client ? (length(
      [for subnet in concat(var.subnets, local.auto_pe_subnet) :
        subnet if subnet.vnet_cidr_index == idx && local.closest_cidr_suffix[idx] == subnet.cidr_suffix && subnet.name != "managed_pe"
      ]
    ) == 1) : false
  } if local.ipam_version == 2]
  vnet_cidrs = (
    length(local.vnet_cidr_suffixes) == 0 ?
    [for vnet in local.vnet_cidrs_no_names :
      merge(vnet, { name : vnet.is_one_subnet ? [for subnet in var.subnets : subnet.name if subnet.vnet_cidr_index == vnet.index][0] : "${vnet.index}" })
    ] : [for idx, suffix in var.vnet_cidr_suffixes : { index : idx, name : "${idx}", cidr_suffix : split("/", suffix)[1], is_one_subnet : false }]
  )

  subnets_consuming_full_vnet = [for vnet in local.vnet_cidrs : vnet.name if vnet.is_one_subnet]

  net_container_bucket = !var.legacy_dr ? "${var.environment == "prod" || var.environment == "dr" ? "prod" : "nonprod"}_${local.short_location_name}" : "${var.environment == "prod" ? var.environment : "nonprod"}_${local.short_location_name}"

  addon_subnets     = [for subnet in var.subnets : subnet if subnet.extend_vnet]
  supernet_requests = { for subnet in var.subnets : subnet.name => { cidr : subnet.next_supernet ? local.net_containers[local.net_container_bucket][var.container_index + 1] : subnet.static_supernet } if subnet.static_supernet != null || subnet.next_supernet }

  subnet_requests = (local.no_vnet_cidr ? local.ipam_version == 2 ?
    [for subnet in concat(var.subnets, local.auto_pe_subnet) :
      { name : subnet.name, subnet_suffix : split("/", subnet.cidr_suffix)[1], vnet_cidr_index : (subnet.vnet_cidr_index == 0 && var.host_cidr_index != 0) ? var.host_cidr_index : tonumber(subnet.vnet_cidr_index) } if !local.vnet_cidrs[subnet.vnet_cidr_index].is_one_subnet
    ] :
    [for subnet in concat(var.subnets, local.auto_pe_subnet) :
      { name : subnet.name, parent_cidr : lookup(local.supernet_requests, subnet.name, null), subnet_suffix : split("/", subnet.cidr_suffix)[1] }
    ] :
    [for subnet in local.addon_subnets :
      { name : subnet.name, parent_cidr : lookup(local.supernet_requests, subnet.name, null), subnet_suffix : split("/", subnet.cidr_suffix)[1] }
    ]
  )

  host_address_spaces = length(data.azurerm_virtual_network.host_vnet) > 0 ? [for address_space in data.azurerm_virtual_network.host_vnet[0].address_space : address_space] : []
}

data "infoblox_ipv4_network_container" "host_vnet_container" {
  for_each = length(local.host_address_spaces) > 0 ? { for index, cidr in local.host_address_spaces : index => { cidr : cidr } } : {}

  network_view = local.network_view
  cidr         = each.value.cidr
}


data "infoblox_ipv4_network_container" "container" {
  count        = local.no_vnet_cidr || local.addon_subnets != [] ? 1 : 0
  cidr         = local.net_containers[local.net_container_bucket][var.container_index]
  network_view = local.network_view
}

data "infoblox_ipv4_network_container" "supernet_requests" {
  for_each     = local.supernet_requests
  cidr         = each.value.cidr
  network_view = local.network_view
}

resource "infoblox_ipv4_network_container" "vnet_container" {
  for_each            = { for vnet in local.vnet_cidrs : vnet.index => vnet if local.ipam_version == 2 && local.network_strategy == "classic" || var.is_host }
  network_view        = local.network_view
  parent_cidr         = data.infoblox_ipv4_network_container.container[0].cidr
  allocate_prefix_len = each.value.cidr_suffix
  comment             = "EC - ${local.vnet_name}"
  ext_attrs = jsonencode({
    "AKA"    = "${data.azurerm_subscription.current.display_name}"
    "Site"   = "N/A"
    "Region" = "${var.location}"
  })

  lifecycle {
    ignore_changes = [
      allocate_prefix_len
    ]
  }

  ##precondition to catch subnets > vnet cidr suffix?
}

resource "infoblox_ipv4_network" "vnet_cidr_list" {
  for_each            = { for subnet in local.subnet_requests : subnet.name => subnet if local.ipam_version == 1 }
  network_view        = local.network_view
  parent_cidr         = each.value.parent_cidr == null ? data.infoblox_ipv4_network_container.container[0].cidr : data.infoblox_ipv4_network_container.supernet_requests[each.value.name].cidr
  allocate_prefix_len = each.value.subnet_suffix
  comment             = "EC - vnet-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}"
  ext_attrs = jsonencode({
    "AKA"    = "${data.azurerm_subscription.current.display_name}"
    "Site"   = "N/A"
    "Region" = "${var.location}"
  })
}

resource "infoblox_ipv4_network" "subnet_cidr_list" {
  for_each            = { for subnet in local.subnet_requests : subnet.name => subnet if local.ipam_version == 2 }
  network_view        = local.network_view
  parent_cidr         = local.is_client ? data.infoblox_ipv4_network_container.host_vnet_container[each.value.vnet_cidr_index].cidr : infoblox_ipv4_network_container.vnet_container[each.value.vnet_cidr_index].cidr
  allocate_prefix_len = each.value.subnet_suffix
  comment             = "EC - snet-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.value.name}"
  ext_attrs = jsonencode({
    "AKA"    = "${data.azurerm_subscription.current.display_name}"
    "Site"   = "N/A"
    "Region" = "${var.location}"
  })


  lifecycle {

    precondition {
      condition     = var.host_cidr_index != 0 ? true : local.network_strategy == "classic" || var.is_host ? local.subnet_cidr_total[each.value.vnet_cidr_index] <= lookup(local.cidr_map, "/${split("/", infoblox_ipv4_network_container.vnet_container[each.value.vnet_cidr_index].cidr)[1]}", 0) : local.subnet_cidr_total[each.value.vnet_cidr_index] <= lookup(local.cidr_map, "/${split("/", data.infoblox_ipv4_network_container.host_vnet_container[tonumber(each.value.vnet_cidr_index - var.host_cidr_index)].cidr)[1]}", 0)
      error_message = "ERROR: Requested total subnet IPs (${local.subnet_cidr_total[tonumber(each.value.vnet_cidr_index - var.host_cidr_index)]}) is out of bounds of existing vnet cidr (${local.network_strategy == "classic" || var.is_host ? infoblox_ipv4_network_container.vnet_container[each.value.vnet_cidr_index].cidr : data.infoblox_ipv4_network_container.host_vnet_container[each.value.vnet_cidr_index].cidr}) on index ${tonumber(each.value.vnet_cidr_index - var.host_cidr_index)}. If you need additional space, add a `vnet_cidr_index` to your subnet definition. See Subnet documentation for details. If you are attempting to resize a subnet, destroy that subnet first, then create it in a follow-up pull request."
    }
    postcondition {
      condition     = self.allocate_prefix_len > split("/", self.parent_cidr)[1]
      error_message = "ERROR: Subnet cidr suffix must be a smaller range than its parent vnet container. If you need additional space, add a `vnet_cidr_index` to your subnet definition. See Subnet documentation for details. "
    }

  }
}