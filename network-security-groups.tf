resource "azurerm_network_security_group" "network_security_group" {
  count = length(local.subnet_with_infoblox) > 0 ? 1 : 0

  name                = "nsg-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-ntwk"
  location            = var.location
  resource_group_name = azurerm_resource_group.network_rg[0].name

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

locals {
  deny_all_nsg_rules = [
    { # DenyAllInbound,4096,Inbound,Deny,*,*,*,*,*
      name                         = "DenyAllInbound",
      priority                     = "4096",
      direction                    = "Inbound",
      access                       = "Deny",
      protocol                     = "*",
      source_port_range            = "*",
      destination_port_range       = "*",
      source_address_prefixes      = "*",
      destination_address_prefixes = "*"
    },
    { # DenyAllOutbound,4096,Outbound,Deny,*,*,*,*,*
      name                         = "DenyAllOutbound",
      priority                     = "4096",
      direction                    = "Outbound",
      access                       = "Deny",
      protocol                     = "*",
      source_port_range            = "*",
      destination_port_range       = "*",
      source_address_prefixes      = "*",
      destination_address_prefixes = "*"
    }
  ]

  aks_type_subnet_name_list = [for subnet in local.subnet_with_infoblox : subnet.name if subnet.type == "aks"]
  aks_type_subnet_name      = length(local.aks_type_subnet_name_list) == 1 ? local.aks_type_subnet_name_list[0] : null
  allow_aks_nsg_rules       = local.aks_type_subnet_name != null ? fileexists("${path.module}/nsg_rules/aks_nsg_rules.csv") ? csvdecode(file("${path.module}/nsg_rules/aks_nsg_rules.csv")) : [] : []
  updated_allow_aks_nsg_rules = [
    for rule in local.allow_aks_nsg_rules : {
      name                         = "${rule.name}",
      priority                     = rule.priority >= 4080 && rule.priority < 4096 ? rule.priority : "Invalid priority, the number provided is ${rule.priority}, it should be between 4080-4095"
      direction                    = rule.direction,
      access                       = rule.access,
      protocol                     = rule.protocol,
      source_port_range            = rule.source_port_range,
      destination_port_range       = rule.destination_port_range,
      source_address_prefixes      = rule.source_address_prefixes == "SNET" ? local.aks_type_subnet_name : rule.source_address_prefixes
      destination_address_prefixes = rule.destination_address_prefixes == "SNET" ? local.aks_type_subnet_name : rule.destination_address_prefixes
    }
  ]

  ase_subnet_name_list = [for subnet in local.subnet_with_infoblox : subnet.name if subnet.type == "app_service_env"]
  ase_subnet_name      = length(local.ase_subnet_name_list) == 1 ? local.ase_subnet_name_list[0] : null
  allow_ase_nsg_rules  = local.ase_subnet_name != null ? fileexists("${path.module}/nsg_rules/ase_nsg_rules.csv") ? csvdecode(file("${path.module}/nsg_rules/ase_nsg_rules.csv")) : [] : []
  updated_allow_ase_nsg_rules = [
    for rule in local.allow_ase_nsg_rules : {
      name                         = "${rule.name}",
      priority                     = rule.priority >= 4055 && rule.priority < 4080 ? rule.priority : "Invalid priority, the number provided is ${rule.priority}, it should be between 4055-4079"
      direction                    = rule.direction,
      access                       = rule.access,
      protocol                     = rule.protocol,
      source_port_range            = rule.source_port_range,
      destination_port_range       = rule.destination_port_range,
      source_address_prefixes      = rule.source_address_prefixes == "SNET" ? local.ase_subnet_name : rule.source_address_prefixes
      destination_address_prefixes = rule.destination_address_prefixes == "SNET" ? local.ase_subnet_name : rule.destination_address_prefixes
    }
  ]


  cog_subnet_name_list = [for subnet in local.subnet_with_infoblox : subnet.name if subnet.type == "cog"]
  cog_subnet_name      = length(local.cog_subnet_name_list) == 1 ? local.cog_subnet_name_list[0] : null
  allow_cog_nsg_rules  = local.cog_subnet_name != null ? fileexists("${path.module}/nsg_rules/cog_nsg_rules.csv") ? csvdecode(file("${path.module}/nsg_rules/cog_nsg_rules.csv")) : [] : []
  updated_allow_cog_nsg_rules = [
    for rule in local.allow_cog_nsg_rules : {
      name                         = "${rule.name}",
      priority                     = rule.priority >= 4040 && rule.priority < 4055 ? rule.priority : "Invalid priority, the number provided is ${rule.priority}, it should be between 4040-4054"
      direction                    = rule.direction,
      access                       = rule.access,
      protocol                     = rule.protocol,
      source_port_range            = rule.source_port_range,
      destination_port_range       = rule.destination_port_range,
      source_address_prefixes      = rule.source_address_prefixes == "SNET" ? local.cog_subnet_name : rule.source_address_prefixes
      destination_address_prefixes = rule.destination_address_prefixes == "SNET" ? local.cog_subnet_name : rule.destination_address_prefixes
    }
  ]

  inbound_https_internal_subnet_name_list   = [for subnet in local.subnet_with_infoblox : subnet.name if (subnet.allow_internal_https_traffic_inbound == true || local.uses_legacy_hub == false) && subnet.type != "aks"]
  inbound_https_internal_subnet_name_joined = length(local.inbound_https_internal_subnet_name_list) >= 1 ? join(",", local.inbound_https_internal_subnet_name_list) : null
  allow_inbound_https_internal_nsg_rules = local.inbound_https_internal_subnet_name_joined != null ? [
    {
      name                         = "AllowInternalHttpsTrafficInbound",
      priority                     = "4020",
      direction                    = "Inbound",
      access                       = "Allow",
      protocol                     = "*",
      source_port_range            = "*",
      destination_port_range       = "443",
      source_address_prefixes      = "10.0.0.0/8,157.121.0.0/16,167.69.0.0/16,172.16.0.0/12,198.187.64.0/18,204.99.0.0/17,206.213.0.0/16",
      destination_address_prefixes = local.inbound_https_internal_subnet_name_joined
    }
  ] : []

  outbound_https_internal_subnet_name_list   = [for subnet in local.subnet_with_infoblox : subnet.name if subnet.allow_internal_https_traffic_outbound == true]
  outbound_https_internal_subnet_name_joined = length(local.outbound_https_internal_subnet_name_list) >= 1 ? join(",", local.outbound_https_internal_subnet_name_list) : null
  allow_outbound_https_internal_nsg_rules = local.outbound_https_internal_subnet_name_joined != null ? [
    {
      name                         = "AllowInternalHttpsTrafficOutbound",
      priority                     = "4020",
      direction                    = "Outbound",
      access                       = "Allow",
      protocol                     = "*",
      source_port_range            = "*",
      destination_port_range       = "443",
      source_address_prefixes      = local.outbound_https_internal_subnet_name_joined,
      destination_address_prefixes = "10.0.0.0/8,157.121.0.0/16,167.69.0.0/16,172.16.0.0/12,198.187.64.0/18,204.99.0.0/17,206.213.0.0/16"
    }
  ] : []

  win_aeth_subnet_name_list = [for subnet in local.subnet_with_infoblox : subnet.name if contains(subnet.nsg_rulesets, "vm-win-aeth")]
  win_aeth_subnet_name      = length(local.win_aeth_subnet_name_list) >= 1 ? join(",", local.win_aeth_subnet_name_list) : null
  allow_win_aeth_nsg_rules  = local.win_aeth_subnet_name != null ? fileexists("${path.module}/nsg_rules/win_aeth_nsg_rules.csv") ? csvdecode(file("${path.module}/nsg_rules/win_aeth_nsg_rules.csv")) : [] : []
  updated_allow_win_aeth_nsg_rules = local.win_aeth_subnet_name != null ? [
    for rule in local.allow_win_aeth_nsg_rules : {
      name                         = "${rule.name}vmwinaeth",
      priority                     = rule.priority >= 3500 && rule.priority < 3600 ? rule.priority : "Invalid priority, the number provided is ${rule.priority}, it should be between 3500-3599",
      direction                    = rule.direction,
      access                       = rule.access,
      protocol                     = rule.protocol,
      source_port_range            = rule.source_port_range,
      destination_port_range       = rule.destination_port_range,
      source_address_prefixes      = rule.source_address_prefixes == "SNET" ? local.win_aeth_subnet_name : rule.source_address_prefixes
      destination_address_prefixes = rule.destination_address_prefixes == "SNET" ? local.win_aeth_subnet_name : rule.destination_address_prefixes
    }
  ] : []

  linux_aeth_subnet_name_list = [for subnet in local.subnet_with_infoblox : subnet.name if contains(subnet.nsg_rulesets, "vm-linux-aeth")]
  linux_aeth_subnet_name      = length(local.linux_aeth_subnet_name_list) >= 1 ? join(",", local.linux_aeth_subnet_name_list) : null
  allow_linux_aeth_nsg_rules  = local.linux_aeth_subnet_name != null ? fileexists("${path.module}/nsg_rules/linux_aeth_nsg_rules.csv") ? csvdecode(file("${path.module}/nsg_rules/linux_aeth_nsg_rules.csv")) : [] : []
  updated_allow_linux_aeth_nsg_rules = local.linux_aeth_subnet_name != null ? [
    for rule in local.allow_linux_aeth_nsg_rules : {
      name                         = "${rule.name}vmlinuxaeth",
      priority                     = rule.priority >= 3600 && rule.priority < 3700 ? rule.priority : "Invalid priority, the number provided is ${rule.priority}, it should be between 3600-3699",
      direction                    = rule.direction,
      access                       = rule.access,
      protocol                     = rule.protocol,
      source_port_range            = rule.source_port_range,
      destination_port_range       = rule.destination_port_range,
      source_address_prefixes      = rule.source_address_prefixes == "SNET" ? local.linux_aeth_subnet_name : rule.source_address_prefixes
      destination_address_prefixes = rule.destination_address_prefixes == "SNET" ? local.linux_aeth_subnet_name : rule.destination_address_prefixes
    }
  ] : []

  win_corp_subnet_name_list = [for subnet in local.subnet_with_infoblox : subnet.name if contains(subnet.nsg_rulesets, "vm-win-corp")]
  win_corp_subnet_name      = length(local.win_corp_subnet_name_list) >= 1 ? join(",", local.win_corp_subnet_name_list) : null
  allow_win_corp_nsg_rules  = local.win_corp_subnet_name != null ? fileexists("${path.module}/nsg_rules/win_corp_nsg_rules.csv") ? csvdecode(file("${path.module}/nsg_rules/win_corp_nsg_rules.csv")) : [] : []
  updated_allow_win_corp_nsg_rules = local.win_corp_subnet_name != null ? [
    for rule in local.allow_win_corp_nsg_rules : {
      name                         = "${rule.name}vmwincorp",
      priority                     = rule.priority >= 3800 && rule.priority < 3900 ? rule.priority : "Invalid priority, the number provided is ${rule.priority}, it should be between 3800-3899",
      direction                    = rule.direction,
      access                       = rule.access,
      protocol                     = rule.protocol,
      source_port_range            = rule.source_port_range,
      destination_port_range       = rule.destination_port_range,
      source_address_prefixes      = rule.source_address_prefixes == "SNET" ? local.win_corp_subnet_name : rule.source_address_prefixes
      destination_address_prefixes = rule.destination_address_prefixes == "SNET" ? local.win_corp_subnet_name : rule.destination_address_prefixes
    }
  ] : []

  linux_corp_subnet_name_list = [for subnet in local.subnet_with_infoblox : subnet.name if contains(subnet.nsg_rulesets, "vm-linux-corp")]
  linux_corp_subnet_name      = length(local.linux_corp_subnet_name_list) >= 1 ? join(",", local.linux_corp_subnet_name_list) : null
  allow_linux_corp_nsg_rules  = local.linux_corp_subnet_name != null ? fileexists("${path.module}/nsg_rules/linux_corp_nsg_rules.csv") ? csvdecode(file("${path.module}/nsg_rules/linux_corp_nsg_rules.csv")) : [] : []
  updated_allow_linux_corp_nsg_rules = local.linux_corp_subnet_name != null ? [
    for rule in local.allow_linux_corp_nsg_rules : {
      name                         = "${rule.name}vmlinuxcorp",
      priority                     = rule.priority >= 3700 && rule.priority < 3800 ? rule.priority : "Invalid priority, the number provided is ${rule.priority}, it should be between 3700-3799",
      direction                    = rule.direction,
      access                       = rule.access,
      protocol                     = rule.protocol,
      source_port_range            = rule.source_port_range,
      destination_port_range       = rule.destination_port_range,
      source_address_prefixes      = rule.source_address_prefixes == "SNET" ? local.linux_corp_subnet_name : rule.source_address_prefixes
      destination_address_prefixes = rule.destination_address_prefixes == "SNET" ? local.linux_corp_subnet_name : rule.destination_address_prefixes
    }
  ] : []

  win_linux_aeth_corp_nsg_rules = concat(local.updated_allow_linux_corp_nsg_rules, local.updated_allow_win_corp_nsg_rules, local.updated_allow_win_aeth_nsg_rules, local.updated_allow_linux_aeth_nsg_rules)

  kv_subnet_name_for_apim_list      = [for subnet in local.subnet_with_infoblox : subnet.name if subnet.name == join(",", [for apim in var.api_management : apim.kv_subnet_name])]
  kv_apim_subnet_name_for_apim_list = [for apim in var.api_management : apim.kv_subnet_name]
  kv_subnet_name_for_apim           = length(local.kv_subnet_name_for_apim_list) == 1 ? local.kv_subnet_name_for_apim_list[0] : null
  kv_pe_apim_rules = local.kv_subnet_name_for_apim != null && length(local.kv_apim_subnet_name_for_apim_list) == 1 ? [
    {
      name                         = "apim-inbound-to-pe"
      priority                     = "4002"
      direction                    = "Inbound"
      access                       = "Allow"
      protocol                     = "TCP"
      source_port_range            = "*"
      destination_port_range       = "*"
      source_address_prefixes      = local.apim_subnet_name
      destination_address_prefixes = local.kv_subnet_name_for_apim
    },
    {
      name                         = "apim-outbound-to-pe"
      priority                     = "4009"
      direction                    = "Outbound"
      access                       = "Allow"
      protocol                     = "TCP"
      source_port_range            = "*"
      destination_port_range       = "*"
      source_address_prefixes      = local.apim_subnet_name
      destination_address_prefixes = local.kv_subnet_name_for_apim
    }
  ] : []
  apim_subnet_name_list = [for subnet in local.subnet_with_infoblox : subnet.name if subnet.type == "apim"]
  apim_subnet_name      = length(local.apim_subnet_name_list) >= 1 ? join(",", local.apim_subnet_name_list) : null
  allow_apim_nsg_rules  = local.apim_subnet_name != null ? fileexists("${path.module}/nsg_rules/apim_nsg_rules.csv") ? csvdecode(file("${path.module}/nsg_rules/apim_nsg_rules.csv")) : [] : []
  updated_allow_apim_nsg_rules = [
    for rule in local.allow_apim_nsg_rules : {
      name                         = "${rule.name}",
      priority                     = rule.priority >= 4000 && rule.priority < 4020 ? rule.priority : "Invalid priority, the number provided is ${rule.priority}, it should be between 4000-4019"
      direction                    = rule.direction,
      access                       = rule.access,
      protocol                     = rule.protocol,
      source_port_range            = rule.source_port_range,
      destination_port_range       = rule.destination_port_range,
      source_address_prefixes      = rule.source_address_prefixes == "SNET" ? local.apim_subnet_name : rule.source_address_prefixes
      destination_address_prefixes = rule.destination_address_prefixes == "SNET" ? local.apim_subnet_name : rule.destination_address_prefixes
    }
  ]

##########################################################################
# NSG Rules for DB
##########################################################################
  db_subnet_name_list = { 
    for key, db_nsg in local.db_nsg_list : key =>[for subnet in local.subnet_with_infoblox : subnet.name if subnet.type == db_nsg.subnet.type]
  }

  db_subnet_name = {
    for key, db_nsg in local.db_nsg_list : key =>length(local.db_subnet_name_list[key]) >= 1 ? join(",", local.db_subnet_name_list[key]) : null
  }

  db_nsg_rules = {
    for key, db_nsg in local.db_nsg_list : key => 
    {
      allow_nsg_rules  = local.db_subnet_name[key] != null ? fileexists("${path.module}/nsg_rules/${db_nsg.nsg.file_name}") ? csvdecode(file("${path.module}/nsg_rules/${db_nsg.nsg.file_name}")) : [] : []
    }
  }

  db_updated_allow_nsg_rules = flatten([
    for key, rules in local.db_nsg_rules : [
      for rule in rules.allow_nsg_rules : {
        name                         = "${rule.name}",
        priority                     = rule.priority >= local.db_nsg_list[key].nsg.rule_priority_from && rule.priority < local.db_nsg_list[key].nsg.rule_priority_to ? rule.priority : "Invalid priority, the number provided is ${rule.priority}, it should be between ${local.db_nsg_list[key].nsg.rule_priority_from} and ${local.db_nsg_list[key].nsg.rule_priority_to}"
        direction                    = rule.direction,
        access                       = rule.access,
        protocol                     = rule.protocol,
        source_port_range            = rule.source_port_range,
        destination_port_range       = rule.destination_port_range,
        source_address_prefixes      = rule.source_address_prefixes == "SNET" ? local.db_subnet_name[key] : rule.source_address_prefixes
        destination_address_prefixes = rule.destination_address_prefixes == "SNET" ? local.db_subnet_name[key] : rule.destination_address_prefixes
      }
    ]
  ])

  db_ase_aks_name_list = [for subnet in local.subnet_with_infoblox : subnet.name if(subnet.type == "app_service_env" || subnet.type == "aks")]
  db_ase_aks_cidr      = length(local.db_ase_aks_name_list) >= 1 ? join(",", local.db_ase_aks_name_list) : null
  db_allow_db_aseaks_nsg_rules = flatten([ 
    for key, db_nsg in local.db_nsg_list : (local.db_ase_aks_cidr != null && local.db_subnet_name[key] != null) ? [
      {
        name                         = db_nsg.nsg.aseaks_outbound_rule_name,
        priority                     = db_nsg.nsg.aseaks_rule_priority,
        direction                    = "Outbound",
        access                       = "Allow",
        protocol                     = "*",
        source_port_range            = "*",
        destination_port_range       = db_nsg.nsg.port_num,
        source_address_prefixes      = local.db_ase_aks_cidr,
        destination_address_prefixes = local.db_subnet_name[key]
      },
      {
        name                         = db_nsg.nsg.aseaks_inbound_rule_name,
        priority                     = db_nsg.nsg.aseaks_rule_priority,
        direction                    = "Inbound",
        access                       = "Allow",
        protocol                     = "*",
        source_port_range            = "*",
        destination_port_range       = db_nsg.nsg.port_num,
        source_address_prefixes      = local.db_ase_aks_cidr,
        destination_address_prefixes = local.db_subnet_name[key]
      }
    ] : []
  ])
##########################################################################
# End NSG Rules for DB
##########################################################################

  nsg_rules_from_csv = fileexists("nsg_rules.csv") ? csvdecode(file("nsg_rules.csv")) : []
  updated_allow_custom_nsg_rules = [
    for rule in local.nsg_rules_from_csv : {
      name                         = "${rule.name}",
      priority                     = var.any_nsg_rule_priority ? rule.priority : rule.priority >= 1 && rule.priority < 3001 ? rule.priority : "Invalid priority, the number provided is ${rule.priority}. Custom NSG rule priority should be between 1-3000."
      direction                    = rule.direction,
      access                       = rule.access,
      protocol                     = rule.protocol,
      source_port_range            = rule.source_port_range,
      destination_port_range       = rule.destination_port_range,
      source_address_prefixes      = rule.source_address_prefixes
      destination_address_prefixes = rule.destination_address_prefixes
    }
  ]


  databricks_subnet_name_list = [for subnet in local.subnet_with_infoblox : subnet.name if subnet.type == "databricks"]
  databricks_subnet_name      = length(local.databricks_subnet_name_list) > 0 ? local.databricks_subnet_name_list[0] : null
  allow_databricks_nsg_rules  = local.databricks_subnet_name != null ? fileexists("${path.module}/nsg_rules/databricks_nsg_rules.csv") ? csvdecode(file("${path.module}/nsg_rules/databricks_nsg_rules.csv")) : [] : []

  network_security_rules_list = length(local.subnet_with_infoblox) > 0 ? concat(local.updated_allow_custom_nsg_rules, local.deny_all_nsg_rules, local.updated_allow_aks_nsg_rules, local.updated_allow_ase_nsg_rules, local.updated_allow_cog_nsg_rules, local.allow_inbound_https_internal_nsg_rules, local.allow_outbound_https_internal_nsg_rules, local.win_linux_aeth_corp_nsg_rules, local.db_updated_allow_nsg_rules, local.db_allow_db_aseaks_nsg_rules, local.allow_databricks_nsg_rules, local.updated_allow_apim_nsg_rules, local.kv_pe_apim_rules) : []

  source_port_input = {
    for rule in local.network_security_rules_list : rule.name => (length(split(",", rule.source_port_range)) > 1) ?
    { source_port_ranges = split(",", rule.source_port_range), source_port_range = null } :
    { source_port_ranges = null, source_port_range = rule.source_port_range }
  }

  destination_port_input = {
    for rule in local.network_security_rules_list : rule.name => (length(split(",", rule.destination_port_range)) > 1) ?
    { destination_port_ranges = split(",", rule.destination_port_range), destination_port_range = null } :
    { destination_port_ranges = null, destination_port_range = rule.destination_port_range }
  }

  source_address_input = {
    for rule in local.network_security_rules_list : rule.name => (length(split(",", rule.source_address_prefixes)) > 1) ?
    { source_address_prefixes = [for item in split(",", rule.source_address_prefixes) : trimspace(item)], source_address_prefix = null } :
    { source_address_prefixes = null, source_address_prefix = rule.source_address_prefixes }
  }

  destination_address_input = {
    for rule in local.network_security_rules_list : rule.name => (length(split(",", rule.destination_address_prefixes)) > 1) ?
    { destination_address_prefixes = [for item in split(",", rule.destination_address_prefixes) : trimspace(item)], destination_address_prefix = null } :
    { destination_address_prefixes = null, destination_address_prefix = rule.destination_address_prefixes }
  }

  nsg_rule_list = [for rule in local.network_security_rules_list : merge(rule, local.source_port_input[rule.name], local.destination_port_input[rule.name], local.source_address_input[rule.name], local.destination_address_input[rule.name])]

  # "The name must begin with a letter or number, end with a letter, number or underscore, and may contain only letters, numbers, underscores, periods, or hyphens."
  validate_nsg_rule_names = alltrue([for rule in local.nsg_rule_list : !can(regex("^[a-zA-Z0-9][a-zA-Z0-9_.-]*[a-zA-Z0-9_]$", rule.name)) ? tobool("${local.ec_error_aheader} ${rule.name} ${local.ec_error_nsg_name1} ${local.ec_error_nsg_name2} ${local.ec_error_zfooter}") : true])

  # Validate that a list of valid IP addresses are being passed to source
  validate_nsg_rule_source_address_prefixes = alltrue([
    for rule in local.nsg_rule_list : alltrue([
      for address in rule.source_address_prefixes :
      contains(local.subnet_names, address) ? true :
      !can(regex(".*/[0-9][0-9]?$", address)) ?
      (!can(cidrnetmask(join("/", [address, "24"]))) ?
      tobool("${local.ec_error_aheader} ${rule.name} ${local.ec_error_nsg_addresses} ${address} ${local.ec_error_zfooter}") : true)
      : !(cidrsubnet(address, 0, 0) == address) ?
      tobool("${local.ec_error_aheader} ${rule.name} ${local.ec_error_nsg_addresses} ${address} ${local.ec_error_zfooter}") : true
    ]) if rule.source_address_prefixes != null
    ]
  )

  # Validate that a list of valid IP addresses are being passed to destination
  validate_nsg_rule_destination_address_prefixes = alltrue([
    for rule in local.nsg_rule_list : alltrue([
      for address in rule.destination_address_prefixes :
      contains(local.subnet_names, address) ? true :
      !can(regex(".*/[0-9][0-9]?$", address)) ?
      (!can(cidrnetmask(join("/", [address, "24"]))) ?
      tobool("${local.ec_error_aheader} ${rule.name} ${local.ec_error_nsg_addresses} ${address} ${local.ec_error_zfooter}") : true)
      : !(cidrsubnet(address, 0, 0) == address) ?
      tobool("${local.ec_error_aheader} ${rule.name} ${local.ec_error_nsg_addresses} ${address} ${local.ec_error_zfooter}") : true
    ]) if rule.destination_address_prefixes != null
    ]
  )

  # Validate that a valid IP address is being passed to source
  validate_nsg_rule_source_address_prefix = alltrue([
    for rule in local.nsg_rule_list :
    can(regex("^[a-zA-Z][a-zA-Z]+|[*]", rule.source_address_prefix)) ? true : # Test if it starts with two letters, since it might be a service tag, such as VirtualNetwork or be '*'. If not, it might be an IP address that needs to be validated
    !can(regex(".*/[0-9][0-9]?$", rule.source_address_prefix)) ?
    (!can(cidrnetmask(join("/", [rule.source_address_prefix, "24"]))) ?
    tobool("${local.ec_error_aheader} ${rule.name} ${rule.source_address_prefix} ${local.ec_error_nsg_address} ${local.ec_error_zfooter}") : true)
    : !(cidrsubnet(rule.source_address_prefix, 0, 0) == rule.source_address_prefix) ?
    tobool("${local.ec_error_aheader} ${rule.name} ${rule.source_address_prefix} ${local.ec_error_nsg_address} ${local.ec_error_zfooter}") : true
    if rule.source_address_prefix != null]
  )

  # Validate that a valid IP address is being passed to destination
  validate_nsg_rule_destination_address_prefix = alltrue([
    for rule in local.nsg_rule_list :
    can(regex("^[a-zA-Z][a-zA-Z]+|[*]", rule.destination_address_prefix)) ? true : # Test if it starts with two letters, since it might be a service tag, such as VirtualNetwork or be '*'. If not, it might be an IP address that needs to be validated
    !can(regex(".*/[0-9][0-9]?$", rule.destination_address_prefix)) ?
    (!can(cidrnetmask(join("/", [rule.destination_address_prefix, "24"]))) ?
    tobool("${local.ec_error_aheader} ${rule.name} ${rule.destination_address_prefix} ${local.ec_error_nsg_address} ${local.ec_error_zfooter}") : true)
    : !(cidrsubnet(rule.destination_address_prefix, 0, 0) == rule.destination_address_prefix) ?
    tobool("${local.ec_error_aheader} ${rule.name} ${rule.destination_address_prefix} ${local.ec_error_nsg_address} ${local.ec_error_zfooter}") : true
    if rule.destination_address_prefix != null]
  )

  outbound_priorities = [for rule in local.nsg_rule_list : rule.priority if lower(rule.direction) == "outbound"]
  inbound_priorities  = [for rule in local.nsg_rule_list : rule.priority if lower(rule.direction) == "inbound"]

  # Validate that no Outbound priorities are conflicting
  validate_outbound_priorities = [for validate_priority in local.outbound_priorities :
    length([for priority in local.outbound_priorities : priority if priority == validate_priority]) == 1 ? true
    : tobool("${local.ec_error_aheader} Outbound ${join(" and ", [for rule in local.nsg_rule_list :
  rule.name if rule.priority == validate_priority])} ${local.ec_error_conflict_priorities} ${local.ec_error_conflict_priorities2} ${local.ec_error_zfooter}")]

  # Validate that no Inbound priorities are conflicting
  validate_inbound_priorities = [for validate_priority in local.inbound_priorities :
    length([for priority in local.inbound_priorities : priority if priority == validate_priority]) == 1 ? true
    : tobool("${local.ec_error_aheader} Inbound ${join(" and ", [for rule in local.nsg_rule_list :
  rule.name if rule.priority == validate_priority])} ${local.ec_error_conflict_priorities} ${local.ec_error_conflict_priorities2} ${local.ec_error_zfooter}")]

}

locals {
  # defined_subnet_names = [for subnet in var.subnets : subnet.name]
  subnet_names         = [for subnet in local.subnet_with_infoblox : subnet.name]
}

resource "azurerm_network_security_rule" "network_security_rules" {
  for_each = { for rule in local.nsg_rule_list : rule.name => rule }

  name                         = each.value.name
  priority                     = each.value.priority
  direction                    = title(lower(each.value.direction))
  access                       = title(lower(each.value.access))
  protocol                     = title(lower(each.value.protocol))
  source_port_range            = each.value.source_port_range
  source_port_ranges           = each.value.source_port_ranges
  destination_port_range       = each.value.destination_port_range
  destination_port_ranges      = each.value.destination_port_ranges
  source_address_prefixes      = each.value.source_address_prefixes == null ? null : [for element in each.value.source_address_prefixes : contains(local.subnet_names, element) ? azurerm_subnet.subnets[element].address_prefixes[0] : element]
  source_address_prefix        = each.value.source_address_prefix == null ? null : contains(local.subnet_names, each.value.source_address_prefix) ? azurerm_subnet.subnets[each.value.source_address_prefix].address_prefixes[0] : each.value.source_address_prefix
  destination_address_prefixes = each.value.destination_address_prefixes == null ? null : [for element in each.value.destination_address_prefixes : contains(local.subnet_names, element) ? azurerm_subnet.subnets[element].address_prefixes[0] : element]
  destination_address_prefix   = each.value.destination_address_prefix == null ? null : contains(local.subnet_names, each.value.destination_address_prefix) ? azurerm_subnet.subnets[each.value.destination_address_prefix].address_prefixes[0] : each.value.destination_address_prefix
  resource_group_name          = azurerm_resource_group.network_rg[0].name
  network_security_group_name  = azurerm_network_security_group.network_security_group[0].name
}

resource "azurerm_subnet_network_security_group_association" "subnets_nsgs_associations" {
  for_each                  = { for subnet in local.subnet_with_infoblox : subnet.name => subnet if subnet.type != "gateway" && subnet.type != "firewall" }
  subnet_id                 = azurerm_subnet.subnets[each.key].id
  network_security_group_id = azurerm_network_security_group.network_security_group[0].id
}
