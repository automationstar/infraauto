variable "line_of_business" {
  type        = string
  description = "Line of Business -> [pss,pcw,hcb,hcd,corp]"

  validation {
    condition     = length(var.line_of_business) <= 4 && can(regex("[a-z]+$", var.line_of_business))
    error_message = "Error: Due to resource naming limits in Azure, line_of_business is too long or contains uppercase characters, numbers, or special characters. Please, provide a lowercase line_of_business with less than 5 characters"
  }
}
variable "application_id" {
  type        = string
  description = "Application ID"

  validation {
    condition     = length(var.application_id) <= 7 && can(regex("^[a-z0-9]+$", var.application_id))
    error_message = "Error: Due to resource naming limits in Azure, application_id is invalid. Please, provide an application_id with less than 8 lowercase-only characters and/or numbers. No other characters are allowed."
  }
}
variable "environment" {
  type        = string
  description = "one of the following environments: [ dev | qa | uat | pt | prod | nonprod | preprod | dr | poc | sit ]"

  validation {
    condition     = contains(["dev", "qa", "uat", "pt", "prod", "nonprod", "preprod", "dr", "poc", "sit"], var.environment)
    error_message = "Error: environment needs to be one of the following: [ dev | qa | uat | pt | prod | nonprod | preprod | dr | poc | sit ]"
  }
}

variable "go_live_date" {
    type        = string
    description = "Date production environment went or will go live"
    default     = null

    validation {
        condition     = var.go_live_date != null ? can(regex("[0-9]{4}-[0-9]{2}-[0-9]{2}", var.go_live_date)) : true
        error_message = "The date must be in format 'YYYY-MM-DD'"
    }
}

variable "location" {
  type        = string
  description = "one of the following regions: [ eastus2 | centralus | westus3 | eastus ]"

  validation {
    condition     = contains(["eastus2", "centralus", "eastus", "westus3"], var.location)
    error_message = "Error: location needs to be one of the following: [ eastus2 | centralus ]"
  }
}

variable "reader_groups" {
  type        = list(string)
  description = "List of AD Group Object IDs that will be granted Reader access to all Resource Groups"
  default     = []
}

variable "dr_tier" {
  type = string
  description = "DR tier for production environments"
  default = null

  validation {
  condition     = var.dr_tier != null ? contains(["1A","1B","1C","1D","1E","2A","2B","2C","2D","2E","3A","3B","3C","3D","3E","4A","4B","4C","4D","4E","5A","5B","5C","5D","5E","9Z"], upper(var.dr_tier)): true 
  error_message = "Error: dr_tier needs to be one of the following: [\"1A\",\"1B\",\"1C\",\"1D\",\"1E\",\"2A\",\"2B\",\"2C\",\"2D\",\"2E\",\"3A\",\"3B\",\"3C\",\"3D\",\"3E\",\"4A\",\"4B\",\"4C\",\"4D\",\"4E\",\"5A\",\"5B\",\"5C\",\"5D\",\"5E\",\"9Z\"]"
  }
}

locals {
  
  dr_tier = var.dr_tier != null ? upper(var.dr_tier) : null

  location_map = {
    "eastus2"   = "use2"
    "centralus" = "usc"
    "eastus"    = "use"
    "westus3"   = "usw3"
  }
  short_location_name       = local.location_map["${var.location}"]
  cross_region_location     = var.location == "eastus2" ? "centralus" : "eastus2"
  short_cross_location_name = local.location_map["${local.cross_region_location}"]
}

variable "kv_admin" {
  type    = list(string)
  default = []
}
variable "kv_user" {
  type    = list(string)
  default = []
}
variable "kv_reader" {
  type    = list(string)
  default = []
}

variable "additional_dns_servers" {
  type    = list(string)
  default = []
}

variable "vnet_cidr" {
  type    = list(string)
  default = []
}

variable "is_host" {
  description = "Flag to determine if this a vnet-only host spoke. Client spokes will use this network for their subnets."
  type        = bool
  default     = false
}

variable "host_cidr_index" {
  description = "Sets the vnet_cidr_index of all subnets, unless otherwise set by the subnet."
  type        = number
  default     = 0
}

variable "host_prefix" {
  description = "Overrides the default `subscription-id-env-region` host name prefix."
  type        = string
  default     = null
}

variable "build_base_resources" {
  description = "Builds base resources (key vault, key, des, managed_pe subnet). Only considered during shared_vnet non-host(client) builds. Defaults to false - hosts and classic spokes will build these resources."
  type        = bool
  default     = false
}

variable "host_index" {
  description = "Determines the index of the host vnet. Hosts will add this to their vnet name; clients will reference said vnet."
  type        = number
  default     = 0
}

variable "cross_region_host_index" {
  description = "Determines the index of the cross region host vnet. Hosts will add this to their vnet name; clients will reference said vnet."
  type        = number
  default     = 0
}

variable "build_custom_key_vault" {
  description = "boolean flag to create custom key vault(90 soft delete days key vault)"
  type        = bool
  default     = false
}

variable "container_index" {
  description = "points to the desired index in the respective list of cidrs inside net_container map"
  type        = number
  default     = 0
}

variable "legacy_dr" {
  description = "flags whether this dr env had subnets built using infoblox and prior to network address changes after v0.34.3"
  type        = bool
  default     = false
}

variable "any_nsg_rule_priority" {
  description = "boolean to allow nsg_rules.csv rules to use priorities above 3000. Defaults to false, available for backwards compatibility. Setting to true prevents auto-approval."
  type        = bool
  default     = false
}

variable "peer_external_vnet" {
  description = "externally managed vnet in the same subscription to peer with"
  type = object({
    name           = optional(string)
    resource_group = optional(string)
  })
  default = {}
}


variable "vnet_cidr_suffixes" {
  description = "determines size of vnet container from infoblox rather than calculate from subnets."
  type        = list(string)
  default     = []
}

variable "internal_use" {
  description = "Internal Use settings for configuring spoke_module. Should not be modified by users."
  type = object({
    ipam_version     = optional(number, 1)
    network_strategy = optional(string, "classic")
  })
  default = {}
}


variable "resource_groups" {
  type    = list(string)
  default = []

  validation {
    condition     = alltrue([for rg in var.resource_groups : !contains(["bkp", "diag", "ntwk", "secr", "mi"], rg)])
    error_message = "Error: ExpressCloud auto-creates the following resource groups: [bkp, diag, ntwk, secr, mi]. Please modify the resource group definition that matches any of these."
  }
}

variable "routing_environment" {
  description = "Determines the hub that a spoke vnet will peer to. Defaults to prod to preserve current non-prod connectivity to existing hubs."
  type        = string
  default     = "nonprod"
}

variable "budgets" {
  description = "List of budgets to apply to resource groups."
  type = list(object({
    name              = string
    resource_group    = optional(string)
    resource_group_id = optional(string)
    amount            = optional(number, 1000)
    time_grain        = optional(string, "Monthly")
    start_date        = optional(string, "YYYY-MM-01")
    threshold         = optional(number, 90)
    notify            = optional(bool, true)
    threshold_type    = optional(string, "Actual")
    emails            = optional(list(string), [])
  }))
  default = []

  validation {
    condition     = alltrue([for budget in var.budgets : budget.resource_group != null || budget.resource_group_id != null])
    error_message = "Please provide a resource_group or resource_group_id."
  }
}

variable "required_tags" {
  description = "tags required by Hybrid Cloud FinOps - KB0043733"
  type = object({
    dataclassification = string
    costcenter         = string
    applicationname    = string
    itpmid             = string
    migration          = string
    itpr               = string
    responsible_svp    = string
    reportingsegment   = string
    businessunit       = string
    environmenttype    = string
    environmentsubtype = string
    resourceowner      = string
    sharedemailaddress = string
  })
  validation {
    condition     = !can(regex("ITPR", var.required_tags.itpmid))
    error_message = "Error: ITPMID is not valid. ITPMs can be found in this table under the header Correlation ID (https://aetnaprod1.service-now.com/now/nav/ui/classic/params/target/cmdb_ci_business_app_list.do%3Fsysparm_userpref_module%3D11133b75870003005f9f578c87cb0bfe%26sysparm_view%3DEnd_User). If your application is not included in this table please use this form (https://itsm.cvs.com/sp_home?id=sc_category&sys_id=31bbeaf8e4001410f877ce457cda6be2) to have your application added. If have questions please reach out to Joe Lindsey."
  }

  validation {
    condition     = contains(["Restricted", "Confidential", "Proprietary", "Public"], var.required_tags.dataclassification)
    error_message = "Error: dataclassification tag can only be one of the following: \"Restricted\" | \"Confidential\" | \"Proprietary\" | \"Public\"."
  }

  validation {
    condition     = contains(["Yes", "No"], var.required_tags.migration)
    error_message = "Error: migration tag can only be one of the following: \"Yes\" | \"No\"."
  }

  # validation {
  #   condition     = contains(["Nathan Frank", "Alan Rosa", "Chandra McMahon", "Kathleen Kadziolka", "Ajoy Kodali", "Amaresh Siva", "Mike Eason"], var.required_tags.responsible_svp)
  #   error_message = "Error: responsible_svp tag can only be one of the following: \"Nathan Frank\" | \"Alan Rosa\" | \"Chandra McMahon\" | \"Kathleen Kadziolka\" | \"Ajoy Kodali\" | \"Amaresh Siva\" | \"Mike Eason\"."
  # }

  validation {
    condition     = contains(["PBM", "PSS", "Retail_LTC", "Corporate_Other", "HCB", "HCD", "PCW"], var.required_tags.reportingsegment)
    error_message = "Error: reportingsegment tag can only be one of the following: \"PBM\" | \"PSS\" | \"Retail_LTC\" | \"Corporate_Other\" | \"HCB\" | \"HCD\" | \"PCW\"."
  }

  validation {
    condition     = var.required_tags.reportingsegment == "PSS" ? var.required_tags.businessunit == "NA" : true
    error_message = "Error: businessunit tag can only be: \"NA\" when reportingsegment = \"PSS\"."
  }

  validation {
    condition     = var.required_tags.reportingsegment == "Retail_LTC" ? contains(["Pharmacy", "Loyalty", "Omnicare", "MinuteClinic"], var.required_tags.businessunit) : true
    error_message = "Error: businessunit tag can only be one of the following: \"Pharmacy\" | \"Loyalty\" | \"Omnicare\" | \"MinuteClinic\" when reportingsegment = \"Retail_LTC\"."
  }

  validation {
    condition     = var.required_tags.reportingsegment == "Corporate_Other" ? var.required_tags.businessunit == "NA" : true
    error_message = "Error: businessunit tag can only be \"NA\" when reportingsegment = \"Corporate_Other\"."
  }

  validation {
    condition     = var.required_tags.reportingsegment == "HCB" ? contains(["Governmental", "Commercial"], var.required_tags.businessunit) : true
    error_message = "Error: businessunit tag can only be on of the following: \"Governmental\" | \"Commercial\" when reportingsegment = \"HCB\"."
  }

  validation {
    condition     = contains(["Prod", "NonProd", "DR"], var.required_tags.environmenttype)
    error_message = "Error: environmenttype tag can only be one of the following: \"Prod\" | \"NonProd\" | \"DR\"."
  }

  validation {
    condition     = contains(["NA", "Dev", "POC", "PT", "QA", "SIT", "Staging", "Training", "Test", "DR"], var.required_tags.environmentsubtype)
    error_message = "Error: environmentsubtype tag can only be one of the following: \"NA\" | \"Dev\" | \"POC\" | \"PT\" | \"QA\" | \"SIT\" | \"Staging\" | \"Training\" | \"Test\" | \"DR\"."
  }

}

variable "optional_tags" {
  description = "optional customer defined tags"
  type        = map(any)
  default     = {}
}

variable "ignore_tag_changes" {
  description = "if true, ignore tag changes after resource creation. Defaults to false."
  type        = bool
  default     = false
}

locals {
  all_subnet_types = ["none", "aks", "app_service_env"]
}

variable "allow_bgp" {
  description = "Allows the use/default behavior of disable_bgp_route_propagation = false on subnets even when using SecureHub2-style hubs."
  type = bool
  default = false

}

variable "subnets" {
  description = "list of subnets. subnet egress_type: cisco_firewall | azure_firewall | aks | pci | none --> default = azure_firewall"
  type = list(object({
    name                                  = string
    type                                  = optional(string, "none")
    cidr                                  = optional(list(string))
    cidr_suffix                           = optional(string)
    vnet_cidr_index                       = optional(number, 0)
    egress_type                           = optional(string, "azure_firewall")
    disable_bgp_route_propagation         = optional(bool, false)
    delegation_type                       = optional(string)
    service_endpoints                     = optional(list(string))
    allow_internal_https_traffic_inbound  = optional(bool, false)
    allow_internal_https_traffic_outbound = optional(bool, false)
    nsg_rulesets                          = optional(list(string), [])
    extend_vnet                           = optional(bool, false)
    static_supernet                       = optional(string)
    next_supernet                         = optional(bool, false)
    delegations = optional(list(object({
      delegation_name            = string
      service_delegation_name    = string
      service_delegation_actions = list(string)
    })))
    routes = optional(list(object({
      route_name             = string,
      address_prefix         = string,
      next_hop_type          = string,
      next_hop_in_ip_address = optional(string)
    })))
    private_endpoints = optional(list(object({
      resource_name       = string
      resource_group_name = string
      name                = optional(string)
      subresource_names   = optional(list(string))
    })))
  }))
  default = []

  validation {
    condition     = alltrue([for subnet in var.subnets : cidrsubnet(subnet.cidr[0], 0, 0) == subnet.cidr[0] if subnet.cidr != null])
    error_message = "Error: One or more of the provided cidr blocks are incorrect! Please, provide a valid cidr block."
  }

  validation {
    condition     = length([for subnet in var.subnets : true if subnet.cidr_suffix != null && !can(regex("^/", subnet.cidr_suffix))]) == 0
    error_message = "Error: A subnet cidr_suffix property needs to be preceeded by a forward slash(/): e.g.: \"/28\" "
  }

  validation {
    condition     = length([for subnet in var.subnets : true if subnet.cidr_suffix != null && subnet.cidr != null]) == 0
    error_message = "Error: A subnet needs to declare either cidr or cidr_suffix, and both were declared in at least one subnet"
  }

  validation {
    condition     = length([for subnet in var.subnets : true if subnet.cidr_suffix != null || subnet.cidr != null]) == length(var.subnets)
    error_message = "Error: A subnet needs to declare either cidr or cidr_suffix, and neither was declared in at least one subnet"
  }

  validation {
    condition     = length([for subnet in var.subnets : true if subnet.type == "aks"]) <= 1
    error_message = "Error: Unsupported subnet type usage. Only one subnet can be of type aks per module call."
  }

  validation {
    condition     = length([for subnet in var.subnets : true if subnet.type == "app_service_env"]) <= 1
    error_message = "Error: Unsupported subnet type usage. Only one subnet can be of type app_service_env per module call."
  }

  validation {
    condition     = alltrue([for cidr in [for subnet in var.subnets : subnet.cidr[0] if((subnet.type == "app_service_env" || subnet.type == "aks") && (subnet.cidr != null))] : tonumber(split("/", cidr)[1]) <= 27 if cidr != null])
    error_message = "Error: the subnet size for a subnet with type \"app_service_env\" or \"aks\" needs to be at least /27"
  }

  validation {
    condition     = alltrue([for cidr_suffix in [for subnet in var.subnets : subnet.cidr_suffix if((subnet.type == "app_service_env" || subnet.type == "aks") && (subnet.cidr_suffix != null))] : tonumber(split("/", cidr_suffix)[1]) <= 27 if cidr_suffix != null])
    error_message = "Error: the subnet size for a subnet with type \"app_service_env\" or \"aks\" needs to be at least /27"
  }

  validation {
    condition     = alltrue([for subnet in var.subnets : subnet.static_supernet == null if subnet.next_supernet])
    error_message = "Error: either static_supernet or next_supernet can be specified for the same subnet"
  }
}

locals {
  #validate supported subnet types
  supported_subnet_types            = [for subnet in var.subnets : (contains(["none", "aks", "app_service_env", "cog", "pe", "vm-win-aeth", "vm-win-corp", "vm-linux-aeth", "vm-linux-corp", "apim", "databricks", "gateway", "firewall"], subnet.type) || contains(local.db_subnet_types_list, subnet.type))]
  validate_supported_subnet_types   = alltrue(local.supported_subnet_types) ? true : tobool("${local.ec_error_aheader} ${local.ec_error_subnet_types} ${local.ec_error_zfooter}")
  
  #validate subnet cidr
  cidr_subnet_size = {
    for key, db_subnet in local.db_subnets_list : key => [for cidr in [
      for subnet in var.subnets : subnet.cidr[0] if(db_subnet.type==subnet.type && (subnet.cidr != null))
    ] : tonumber(split("/", cidr)[1]) <= db_subnet.size if cidr != null && try(db_subnet.size,null) != null]
  }
  validate_cidr_subnet_size = [
    for key, db_subnet in local.db_subnets_list : {
      validate_subnet_size  = alltrue(local.cidr_subnet_size[key]) ? true : tobool("${local.ec_error_aheader} Error: the subnet size for a subnet with type \"${db_subnet.type}\" needs to be at least /${db_subnet.size} ${local.ec_error_zfooter}")
    }
  ]

  #validate subnet cidr_suffix
  cidr_suffix_subnet_size = {
    for key, db_subnet in local.db_subnets_list : key => [for cidr_suffix in [
      for subnet in var.subnets : subnet.cidr_suffix if(db_subnet.type==subnet.type && (subnet.cidr_suffix != null))
      ] : tonumber(split("/", cidr_suffix)[1]) <= db_subnet.size if cidr_suffix != null && try(db_subnet.size, null) != null]
  }
  validate_cidr_suffix_subnet_size = [
    for key, db_subnet in local.db_subnets_list : {
      validate_subnet_size  = alltrue(local.cidr_suffix_subnet_size[key]) ? true : tobool("${local.ec_error_aheader} Error: the subnet size for a subnet with type \"${db_subnet.type}\" needs to be at least /${db_subnet.size} ${local.ec_error_zfooter}")
    }
  ]
}

variable "external_private_endpoints" {
  description = "private endpoints for networks not managed by this terraform module"
  type = list(object({
    name                = string
    subnet_id           = string
    resource_group_name = string
    resource_name       = string
  }))
  default = []
}

variable "log_analytics_workspace" {
  description = "Log Analytics Workspaces - choose either \"standard\" or \"custom\". In case of custom also pass a log_analytics_workspace_specs variable."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "custom", "none"], var.log_analytics_workspace)
    error_message = "Error: log_analytics_workspace should be one of the following: 'standard', 'custom', or 'none'."
  }
}

variable "log_analytics_workspace_specs" {
  description = "Log Analytics Workspaces"
  type = object({
    sku               = string
    retention_in_days = string
    ud_resource_group = optional(string)
  })
  default = {
    retention_in_days = "30"
    sku               = "PerGB2018"
    ud_resource_group = "none"
  }
}

variable "use_ud_law_fl" {
  description = "boolean flag to signal whether to use the log_analytics_workspace for NSG Flow Logs. Defaults to true"
  type        = bool
  default     = true
}

variable "use_global_law_fl" {
  description = "boolean flag to signal whether to use log-securehub-global-ntwk-flowlogs in the hub, when use_ud_law_fl is false. Defaults to false."
  type        = bool
  default     = false
}

variable "enable_subscription_diagnostics" {
  description = "Boolean flag to enable azure monitor diagnostics on the subscription to be collected. Defaults to false."
  type        = bool
  default     = false
}

##########################################################################
# Diagnostics Objects
#
#
# Use Example
# diagnostic_objects = {
#   log = [
#       #["Category name"]
#    ]
#   metric = [
#       #["Category name",  "Diagnostics Enabled(true/false)", "Retention Enabled(true/false)", Retention_period]
#   ]
#}
##########################################################################
variable "subscription_diagnostic_objects" {
  description = "Diagnostic Objects = { log = [#[\"Category Name\", \"Retention Enabled (true/false)\", \"Retention Period\"]] metric = [#[\"Category Name\", \"Diagnostic Enabled(true/false)\", \"Retention Enabled (true/false)\", \"Retention Period\"]]"
  type        = map(any)
  default = {
    log = [
      #["Category name", "Retention Enabled(true/false)", Retention_period]
      ["Administrative"],
      ["Security"],
      ["ServiceHealth"],
      ["Alert"],
      ["Recommendation"],
      ["Policy"],
      ["Autoscale"],
      ["ResourceHealth"]
    ]
    metric = []
  }
}

variable "storage_accounts" {
  description = "a list of user-defined storage account objects"
  type = list(object({
    name                     = string
    ud_resource_group        = string
    account_tier             = optional(string, "Standard")
    account_replication_type = optional(string, "LRS")
    account_kind             = optional(string, "StorageV2")
    subnet_name              = string
    hns_enabled              = optional(bool, false)
    pe_subresources          = optional(list(string), ["blob"])
    cmk_id                   = optional(string)
    cmk_managed_identity_id  = optional(string)
    custom_domain            = optional(string)
    use_subdomain            = optional(bool, true)
    sas_expiration_period    = optional(string, "06.23:00:00")
    sftp_enabled             = optional(bool, false)
    public_network_access_enabled = optional(bool, false) #BY SECURITY EXEMPTION ONLY
  }))
  default = []
  validation {
    condition     = alltrue([for st in var.storage_accounts : alltrue([for subresource in st.pe_subresources : contains(["blob", "blob_secondary", "table", "table_secondary", "queue", "queue_secondary", "file", "file_secondary", "web", "web_secondary", "dfs", "dfs_secondary"], subresource)])])
    error_message = "Error: Invalid subresource provided. Valid values are: 'blob','blob_secondary','table','table_secondary','queue','queue_secondary','file','file_secondary','web','web_secondary','dfs','dfs_secondary'."
  }
  validation {
    condition     = alltrue([for st in var.storage_accounts : contains(["BlobStorage", "BlockBlobStorage", "FileStorage", "StorageV2"], st.account_kind)])
    error_message = "Error: Invalid account kind provided. Valid values are: 'BlobStorage', 'BlockBlobStorage', 'FileStorage', and 'StorageV2'."
  }
  validation {
    condition     = alltrue([for st in var.storage_accounts : contains(["FileStorage", "BlockBlobStorage"], st.account_kind) ? st.account_tier == "Premium" : true])
    error_message = "Error: Invalid combination of account_kind and account_tier. For 'FileStorage', 'BlockBlobStorage' account_tier must be set to 'Premium'."
  }
  validation {
    condition     = alltrue([for st in var.storage_accounts : contains(["Premium"], st.account_tier) ? st.account_kind != "BlobStorage" : true])
    error_message = "Error: Invalid combination of account_kind and account_tier. Premium account_tier Storage Accounts cannot have account_kind of BlobStorage"
  }
  validation {
    condition     = alltrue([for st in var.storage_accounts : st.account_tier == "Premium" ? contains(["LRS", "ZRS"], st.account_replication_type) : true])
    error_message = "Error: Invalid combination of account_replication_type and account_tier. For account_tier='Premium', account_replication_type must be one of the following: LRS, ZRS"
  }
  validation {
    condition     = alltrue([for st in var.storage_accounts : st.sftp_enabled == true ? st.hns_enabled == true : true])
    error_message = "Error: When sftp_enabled is set to 'true', hns_enabled must also be set to 'true'"
  }
}

variable "diag_st_private_endpoints_subresource_types" {
  type    = list(string)
  default = ["blob", "web"]
}


# variable "diag_st_private_endpoints_subresource_types" {
#   type    = list(string)
#   default =  ["blob","web"]
# }

# variable "storage_account_subnet" {
#   type    = string
#   default = null
# }

variable "cognitive_services" {
  description = "a list of azure cognitive service account definitions"
  type = list(object({
    name                   = string
    kind                   = string
    sku_name               = string
    location               = optional(string, "eastus2")
    custom_subdomain       = optional(string)
    subnet_name            = optional(string)
    external_subnet_id     = optional(string)
    external_subnet_region = optional(string)
    storage_account_id     = optional(string)
    storage_account_name   = optional(string)
    storage_identity_id    = optional(string)
    ud_resource_group      = optional(string)
    model                  = optional(string)
    model_version          = optional(string, "0613")
    capacity               = optional(number, 10)
    user_group             = optional(string)
    fqdns                  = optional(list(string), []) #Requires security exception
    local_auth_enabled     = optional(bool, false)
    ai_governance_tag      = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for cog in var.cognitive_services : cog.custom_subdomain != null ? cog.custom_subdomain == lower(cog.custom_subdomain) : true])
    error_message = "Error: custom subdomains only support lowercase letters, numbers, and dashes."
  }
  validation {
    condition     = alltrue([for cog in var.cognitive_services : contains(["Academic", "AnomalyDetector", "Bing.Autosuggest", "Bing.Autosuggest.v7", "Bing.CustomSearch", "Bing.Search", "Bing.Search.v7", "Bing.Speech", "Bing.SpellCheck", "Bing.SpellCheck.v7", "CognitiveServices", "ComputerVision", "ContentModerator", "CustomSpeech", "CustomVision.Prediction", "CustomVision.Training", "Emotion", "Face", "FormRecognizer", "ImmersiveReader", "LUIS", "LUIS.Authoring", "MetricsAdvisor", "OpenAI", "Personalizer", "QnAMaker", "Recommendations", "SpeakerRecognition", "Speech", "SpeechServices", "SpeechTranslation", "TextAnalytics", "TextTranslation", "WebLM"], cog.kind)])
    error_message = "Error: invalid Cognitive Services type. Must be one of the following: 'Academic', 'AnomalyDetector', 'Bing.Autosuggest', 'Bing.Autosuggest.v7', 'Bing.CustomSearch', 'Bing.Search', 'Bing.Search.v7', 'Bing.Speech', 'Bing.SpellCheck', 'Bing.SpellCheck.v7', 'CognitiveServices', 'ComputerVision', 'ContentModerator', 'CustomSpeech', 'CustomVision.Prediction', 'CustomVision.Training', 'Emotion', 'Face', 'FormRecognizer', 'ImmersiveReader', 'LUIS', 'LUIS.Authoring', 'MetricsAdvisor', 'OpenAI', 'Personalizer', 'QnAMaker', 'Recommendations', 'SpeakerRecognition', 'Speech', 'SpeechServices', 'SpeechTranslation', 'TextAnalytics', 'TextTranslation', 'WebLM'. "
  }
  validation {
    condition     = alltrue([for cog in var.cognitive_services : contains(["F0", "F1", "S0", "S", "S1", "S2", "S3", "S4", "S5", "S6", "P0", "P1", "P2", "E0", "DC0"], cog.sku_name)])
    error_message = "Error: invalid SKU. Must be one of the following: 'F0', 'F1', 'S0', 'S', 'S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'P0', 'P1', 'P2', 'E0', 'DC0'."
  }
  validation {
    condition     = alltrue([for cog in var.cognitive_services : cog.subnet_name != null || cog.external_subnet_id != null])
    error_message = "Error: No subnet. Must declare either a subnet_name or an external_subnet_id."
  }

  # validation {
  #   condition     = alltrue([for cog in var.cognitive_services : cog.model != null ? contains(["gpt-35-turbo", "gpt-4", "gpt-35-turbo-16k", "gpt-4-32k", "text-embedding-ada-002"], cog.model) : true])
  #   error_message = "Error: Invalid model. Model must be one of the following: 'gpt-35-turbo','gpt-35-turbo-16k','gpt-4','gpt-4-32k','text-embedding-ada-002'."
  # }
  # validation {
  #   condition     = alltrue([for cog in var.cognitive_services : cog.capacity < 121])
  #   error_message = "Error: Capacity too large. Set capacity less than 120 (120K TPM)."
  # }
}

variable "ai_models" {
  description = "list of additional AI model definitions"
  type = list(object({
    name          = string
    ai_name       = string
    model         = string
    model_version = optional(string, "0613")
    capacity      = optional(number, 10)
  }))
  default = []

  # validation {
  #   condition     = alltrue([for model in var.ai_models : model.model != null ? contains(["gpt-35-turbo", "gpt-4", "gpt-35-turbo-16k", "gpt-4-32k", "text-embedding-ada-002"], model.model) : true])
  #   error_message = "Error: Invalid model. Model must be one of the following: 'gpt-35-turbo','gpt-35-turbo-16k','gpt-4','gpt-4-32k', 'text-embedding-ada-002'."
  # }
  # validation {
  #   condition     = alltrue([for model in var.ai_models : model.capacity < 121])
  #   error_message = "Error: Capacity too large. Set capacity less than 120 (120K TPM)."
  # }
}

variable "search_services" {
  description = "a list of user-defined Cognitive Search Services"
  type = list(object({
    name               = string
    subnet_name        = optional(string)
    external_subnet_id = optional(string)
    sku_name           = optional(string, "standard")
    replica_count      = optional(string, "1")
    partition_count    = optional(string, "1")
    ud_resource_group  = optional(string)
    deploy_mode        = optional(string, "api")
    disable_local_auth = optional(bool, true)
  }))
  default = []

  validation {
    condition     = alltrue([for srch in var.search_services : srch.subnet_name != null || srch.external_subnet_id != null])
    error_message = "Error: No subnet. Must declare either a subnet_name or an external_subnet_id."
  }
  validation {
    condition     = alltrue([for srch in var.search_services : contains(["basic", "free", "standard", "standard2", "standard3", "storage_optimized_l1", "storage_optimized_l2"], srch.sku_name)])
    error_message = "Error: Invalid SKU. Must be one of the following: 'basic', 'free', 'standard', 'standard2', 'standard3', 'storage_optimized_l1', 'storage_optimized_l2'. "
  }
}

variable "app_service_plans" {
  description = "a list of azure app services definitions"
  type = list(object({
    name                 = string
    os_type              = optional(string, "Linux")
    sku_name             = optional(string, "P1v3")
    subnet_name          = optional(string)
    ase_name             = optional(string)
    ase_rg               = optional(string)
    ud_resource_group    = optional(string)
    min_instances        = optional(number, 1)
    max_instances        = optional(number, 3)
    scale_up_threshold   = optional(number, 75)
    scale_down_threshold = optional(number, 35)
    autoscale            = optional(bool, true)
  }))
  default = []
  validation {
    condition     = alltrue([for plan in var.app_service_plans : (startswith(plan.sku_name, "I") && (plan.subnet_name != null || (plan.ase_name != null && plan.ase_rg != null))) || !startswith(plan.sku_name, "I")])
    error_message = "Error: You must assign a subnet_name or ase_name and ase_rg when using an Isolated Service Plan sku_name."
  }
  validation {
    condition     = alltrue([for plan in var.app_service_plans : contains(["F1", "D1", "B1", "B2", "B3", "S1", "S2", "S3", "P1v2", "P2v2", "P3v2", "P0v3", "P1v3", "P1mv3", "P2v3", "P2mv3", "P3v3", "P3mv3", "P4mv3", "P5mv3", "I1", "I2", "I3", "I1v2", "I2v2", "I3v2", "I4v2", "I5v2", "I6v2", "WS1", "WS2", "WS3", "Y1", "SHARED", ], plan.sku_name)])
    error_message = "Error: Invalid sku_name. Please use a valid SKU from https://azure.microsoft.com/en-us/pricing/details/app-service/windows/."
  }
}

variable "function_apps" {
  type = list(object({
    name                          = string
    ud_app_service_plan           = string
    ud_storage_account            = string
    integrated_subnet_name        = optional(string)
    pe_subnet_name                = optional(string)
    external_pe_subnet_id         = optional(string)
    external_integrated_subnet_id = optional(string)
    site_config                   = optional(any, {})
    ud_resource_group             = optional(string)
    ud_user_identity              = optional(string) # managed identity block reference
    user_identity_name            = optional(string)
    user_identity_resource_group  = optional(string)
    public_network_access_enabled = optional(bool, false) #optional flag, false by default
  }))
  default = []

  validation {
    condition     = alltrue([for app in var.function_apps : length(app.ud_app_service_plan) > 0])
    error_message = "Error: You must have an ASP created in order to provision a function app."
  }

  validation {
    condition     = alltrue([for app in var.function_apps : app.user_identity_name != null ? app.user_identity_resource_group != null : true])
    error_message = "When using `user_identity_name`, `user_identity_resource_group` must be provided."
  }
}

variable "logic_apps" {
  type = list(object({
    name                          = string
    ud_app_service_plan           = string
    site_config                   = optional(any, {})
    ud_resource_group             = optional(string)
    ud_storage_account            = string
    pe_subnet_name                = optional(string)
    external_pe_subnet_id         = optional(string)
    integrated_subnet_name        = optional(string)
    external_integrated_subnet_id = optional(string)
    account_share                 = optional(string)
    app_settings                  = optional(map(string))
  }))
  default = []
}

variable "app_configurations" {
  type = list(object({
    name               = string
    ud_resource_group  = optional(string)
    subnet_name        = optional(string, "")
    external_subnet_id = optional(string)
    local_auth_enabled = optional(bool, false)
  }))
  default = []
}

variable "aks_cluster" {
  description = "aks cluster parameters"
  type = object({
    subnet_name                                         = optional(string)
    external_vnet_id                                    = optional(string)
    external_subnet_id                                  = optional(string)
    external_subnet_route_table_id                      = optional(string)
    external_log_analytics_workspace_resource_id        = optional(string)
    sku_tier                                            = optional(string, "Standard")
    kubernetes_version                                  = optional(string)
    network_plugin                                      = optional(string, "kubenet")
    cluster_admin_group_object_ids                      = optional(list(string), [])
    cluster_writer_group_object_ids                     = optional(list(string), [])
    cluster_reader_group_object_ids                     = optional(list(string), [])
    privileged_service_principal_object_id              = optional(string, "")
    acr_integration_id                                  = optional(string, "")
    key_vault_admin_group_object_ids                    = optional(list(string), [])
    key_vault_secrets_provider                          = optional(bool, false)
    key_vault_secrets_provider_secret_rotation_enabled  = optional(bool, true)
    key_vault_secrets_provider_secret_rotation_interval = optional(string, "2m")
    open_service_mesh_enabled                           = optional(bool, true)
    web_app_routing_enabled_preview                     = optional(bool, false)
    workload_identity_enabled                           = optional(bool, false)
    namespaces                                          = optional(list(string), [])
    local_account_disabled                              = optional(bool, true)
    legacy_argo                                         = optional(bool, false)
    random_suffix                                       = optional(bool, false)
    index                                               = optional(number)
    loadBalancerIp                                      = optional(string, "")
    service_mesh                                        = optional(string, null)
    auto_loadBalancerIp                                 = optional(bool, false)
  })
  default = {}
  validation {
    condition = concat(var.aks_cluster.cluster_admin_group_object_ids,
      var.aks_cluster.cluster_writer_group_object_ids,
      var.aks_cluster.cluster_reader_group_object_ids) == distinct(
      concat(var.aks_cluster.cluster_admin_group_object_ids,
        var.aks_cluster.cluster_writer_group_object_ids,
    var.aks_cluster.cluster_reader_group_object_ids))
    error_message = "Error: The same group object ID was used in multiple roles. Admin, Writer, and Reader Group Object ID lists must be unique."
  }
  validation {
    condition     = contains(["Free", "Paid", "Standard"], var.aks_cluster.sku_tier)
    error_message = "Error: Sku tier must be Free, Paid, or Standard."
  }

  validation {
    condition     = var.aks_cluster.web_app_routing_enabled_preview ? var.aks_cluster.key_vault_secrets_provider == true : true
    error_message = "Error: If web_app_routing_enabled_preview = 'true', key_vault_secrets_provider must also = 'true'"
  }

  validation {
    condition     = alltrue([for ns in var.aks_cluster.namespaces : ns == lower(ns) && length(ns) <= 63])
    error_message = "Error: Please provide namespaces that are no more than 63 characters with numbers, hyphens and lowercase-only characters."
  }

  validation {

    condition     = var.aks_cluster.random_suffix == true && var.aks_cluster.index == null || var.aks_cluster.random_suffix == false && var.aks_cluster.index != null || var.aks_cluster.random_suffix == false && var.aks_cluster.index == null
    error_message = "Error: aks_cluster block - Please only use either a 'random_suffix' or an 'index'. You can't use both at the same time."

  }

}

variable "disable_watcher" {
  type = bool
  default = false
  description = "Disables network watcher flow logs for peering when no NetworkWatcher exists. Only use for testing."
}

variable "aks_default_node_pool" {
  description = "aks default node pool parameters"
  type = object({
    name                         = string
    enable_auto_scaling          = bool
    max_count                    = optional(number)
    min_count                    = optional(number)
    node_count                   = optional(number)
    vm_size                      = string
    zones                        = list(string)
    max_pods                     = number
    only_critical_addons_enabled = optional(bool)
    orchestrator_version         = optional(string)
    node_taints                  = optional(list(string))
    enable_host_encryption       = optional(bool, true)
  })
  default = {
    name                = "default"
    enable_auto_scaling = false
    node_count          = 3
    vm_size             = "Standard_D8s_v3"
    zones               = ["1", "2", "3"]
    max_pods            = 30
  }
}

variable "aks_extra_node_pools" {
  description = "list of aks extra node pool parameters"
  type = list(object({
    name                   = string
    mode                   = optional(string)
    enable_auto_scaling    = bool
    max_count              = optional(number)
    min_count              = optional(number)
    node_count             = optional(number)
    os_type                = optional(string)
    vm_size                = string
    zones                  = list(string)
    max_pods               = number
    orchestrator_version   = optional(string)
    labels                 = optional(map(string), {})
    node_taints            = optional(list(string))
    enable_host_encryption = optional(bool, true)
    vm_max_map_count       = optional(number)
  }))

  default = []
}

variable "service_bus_namespace" {
  description = "list of service bus configurations"
  type = list(object({
    name                              = string
    capacity                          = optional(number, 1)
    is_zone_redundant                 = optional(bool)
    subnet_name                       = optional(string)
    external_subnet_id                = optional(string)
    infrastructure_encryption_enabled = optional(bool, true)
    trusted_services_allowed          = optional(bool, false)
    local_auth_enabled                = optional(bool, false)
  }))
  default = []

  validation {
    condition     = alltrue([for sb in var.service_bus_namespace : contains([1, 2, 4, 8, 16], sb.capacity)])
    error_message = "Error: Capacity needs to be one of the following: [ 1 | 2 | 4 | 8 | 16 ]."
  }
}

variable "service_bus_entities" {
  description = "list of types of service bus entities and their respective configurations"
  type = list(object({
    name                                    = string
    type                                    = string
    namespace_name                          = string
    max_message_size_in_kilobytes           = optional(number)           # Both
    max_size_in_megabytes                   = optional(number)           # Both
    requires_duplicate_detection            = optional(bool)             # Both
    default_message_ttl                     = optional(string)           # Both
    duplicate_detection_history_time_window = optional(string)           # Both
    status                                  = optional(string)           # Both
    enable_batched_operations               = optional(bool)             # Both
    auto_delete_on_idle                     = optional(string)           # Both
    enable_partitioning                     = optional(bool)             # Both
    enable_express                          = optional(bool)             # Both
    lock_duration                           = optional(string)           # Queue only
    dead_lettering_on_message_expiration    = optional(bool)             # Queue only
    forward_to                              = optional(string)           # Queue only
    forward_dead_lettered_messages_to       = optional(string)           # Queue only
    requires_session                        = optional(bool)             # Queue only
    max_delivery_count                      = optional(number)           # Queue only
    support_ordering                        = optional(bool)             # Topic only
    queue_data_senders                      = optional(list(string), []) # Queue Only
    queue_data_receivers                    = optional(list(string), []) # Queue Only
    topic_data_senders                      = optional(list(string), []) # Topic Only
  }))
  default = []
}

variable "service_bus_subscriptions" {
  description = "list of subscriptions config to attach to topics"
  type = list(object({
    name                                      = string
    topic_name                                = string
    namespace_name                            = string
    max_delivery_count                        = optional(number, 10)
    auto_delete_on_idle                       = optional(string)
    default_message_ttl                       = optional(string)
    lock_duration                             = optional(string)
    status                                    = optional(string)
    requires_session                          = optional(bool)
    forward_to                                = optional(string)
    forward_dead_lettered_messages_to         = optional(string)
    enable_batched_operations                 = optional(bool)
    dead_lettering_on_message_expiration      = optional(bool)
    dead_lettering_on_filter_evaluation_error = optional(bool)
    client_scoped_subscription_enabled        = optional(bool)
    client_scoped_subscription = optional(object({
      is_client_scoped_subscription_shareable = optional(bool)
      is_client_scoped_subscription_durable   = optional(bool)
    }))
    subscription_data_receivers = optional(list(string), [])
  }))
  default = []
}

variable "service_bus_subscription_rules" {
  description = "list of subscription rules to attatch to a subscription"
  type = list(object({
    name              = string
    subscription_name = string
    filter_type       = string
    sql_filter        = optional(string)
    action            = optional(string)
    correlation_filter = optional(object({
      content_type        = optional(string)
      correlation_id      = optional(string)
      label               = optional(string)
      message_id          = optional(string)
      reply_to            = optional(string)
      reply_to_session_id = optional(string)
      session_id          = optional(string)
      to                  = optional(string)
      properties          = optional(map(string))
    }))
  }))
  default = []
}

variable "key_vaults" {
  description = "user defined key vaults"
  type = list(object({
    name                       = string
    resource_group             = optional(string)
    resource_group_name        = optional(string)
    purge_protection_enabled   = optional(bool, true)
    soft_delete_retention_days = optional(number, 7)
    sku_name                   = optional(string, "standard")
    key_vault_admin            = optional(list(string), [])
    ud_mi_key_vault_admin      = optional(list(string), [])
    secrets_user               = optional(list(string), [])
    ud_mi_secrets_user         = optional(list(string), [])
    crypto_user                = optional(list(string), [])
    ud_mi_crypto_user          = optional(list(string), [])
    subnet_name                = optional(string)
    external_subnet_id         = optional(string)
    keys                       = optional(list(object({
      name                     = string
      enable_rotation          = optional(bool, true)
    })),[])
  }))
  default = []

  validation {
    condition     = length([for kv in var.key_vaults : true if kv.resource_group != null && kv.resource_group_name != null]) == 0
    error_message = "Error: A key vault needs to declare either resource_group or resoource_group_name, and both were declared in at least one key vault"
  }
  validation {
    condition     = alltrue([for kv in var.key_vaults : true if can(regex("^[a-z0-9]+$", var.key_vaults.name))])
    error_message = "Error: Due to resource naming limits in Azure, one of your Key Vault Names is invalid. Please, provide a name with lowercase-only characters and/or numbers. No other characters are allowed."
  }


  #  NOTE: Not including this because of private endpoint without DNS might causes issues with CMK?
  #  NOTE: Also, because previous user defined Key Vaults may have already created private endpoints using a different method, this may cause conflicts if required
  #  validation {
  #    condition     = alltrue([for kv in var.key_vaults : kv.subnet_name != null || kv.external_subnet_id != null])
  #    error_message = "Error: Must declare either a subnet_name and or an external_subnet_id for each key vault."
  #  }
}

variable "ud_managed_identities" {
  description = "user defined managed identities"
  type = list(object({
    name                = string
    resource_group_name = optional(string)
    resource_group      = optional(string)
    ud_resource_group   = optional(string)
    env                 = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for mi in var.ud_managed_identities : (mi.env == null ? true : contains(["dev", "qa", "uat", "stg", "pt", "prod", "nonprod", "preprod", "dr", "poc"], mi.env))])
    error_message = "Error: env must be one of: [ dev | qa | uat | stg | pt | prod | nonprod | preprod | dr | poc ]"
  }

  validation {
    condition     = alltrue([for mi in var.ud_managed_identities : mi.resource_group == null || mi.resource_group_name == null])
    error_message = "Error: Can not specify both resource_group_name and resource_group"
  }

  validation {
    condition     = alltrue([for mi in var.ud_managed_identities : mi.ud_resource_group == null])
    error_message = "Error: The ud_resource_group argument should no longer be used. Please switch to using \"resource_group_name\" if the resource group is not defined in your spoke file or \"resource_group\" if the resource group is defined in your spoke file"
  }

}

variable "aks_federated_credentials" {
  description = "user defined aks federated credentials"
  type = list(object({
    name                                     = string
    kubernetes_service_account_name          = string
    kubernetes_namespace                     = string
    user_defined_managed_identity_name       = optional(string)
    external_managed_identity_name           = optional(string)
    external_managed_identity_resource_group = optional(string)
    non_default                              = optional(bool, false)
  }))
  default = []

  validation {
    condition     = length([for fc in var.aks_federated_credentials : true if(fc.user_defined_managed_identity_name == null && fc.external_managed_identity_name != null) || (fc.user_defined_managed_identity_name != null && fc.external_managed_identity_name == null)]) == length(var.aks_federated_credentials)
    error_message = "Error: A federated credential must have one type of managed identity defined"
  }

  validation {
    condition     = length([for fc in var.aks_federated_credentials : true if fc.external_managed_identity_name != null && fc.external_managed_identity_resource_group == null]) == 0
    error_message = "Error: An external managed identity requires a resource group to be specified"
  }

  validation {
    condition     = alltrue([for fc in var.aks_federated_credentials : (fc.non_default || fc.kubernetes_service_account_name == "${fc.kubernetes_namespace}-sa")])
    error_message = "Error: If non_default is false, kubernetes_service_account_name must be the kubernetes_namespace with an '-sa' suffix. If non_default is true, kubernetes_service_account_name can be anything."
  }
}

variable "gha_federated_credentials" {
  description = "user defined github actions federated credentials"
  type = list(object({
    name                               = string
    user_defined_managed_identity_name = string
    github_organization                = string
    github_repository                  = string
    github_entity                      = string
    github_entity_value                = optional(string)
    cluster_admin                      = optional(bool, false)
    aks_deploy = optional(object({
      namespaces = list(string)
    }))
  }))
  default = []

  validation {
    condition     = alltrue([for fc in var.gha_federated_credentials : contains(["Environment", "Branch", "Pull Request", "Tag"], fc.github_entity)])
    error_message = "Error: A federated credential must have an appropriate github_entity defined of type \"Environment\", \"Branch\", \"Pull Request\", or \"Tag\""
  }

  validation {
    condition     = length([for fc in var.gha_federated_credentials : true if fc.github_entity != "Pull Request" && fc.github_entity_value == null]) == 0
    error_message = "Error: If specifying a github_entity of type \"Environment\", \"Branch\", or \"Tag\", then github_entity_value is required"
  }
}


variable "virtual_machines" {
  description = "a list of virtual machine configurations"
  type = list(object({
    name                          = string
    subnet_name                   = string
    ud_resource_group             = string
    vm_size                       = optional(string, "Standard_DS1_v2")
    os_type                       = optional(string, "linux")
    os_disk_name                  = optional(string)
    os_disk_caching               = optional(string, "ReadWrite")
    os_disk_storage_account_type  = optional(string, "Standard_LRS")
    encryption_at_host            = optional(bool, true)
    private_ip_address_allocation = optional(string, "Dynamic")
    private_ip_address            = optional(string)
    ip_index                      = optional(number)
    managed_disks = optional(list(object({
      name    = optional(string)
      lun     = optional(number, 1)
      caching = optional(string, "ReadWrite")
    })))
  }))
  default = []

  validation {
    condition     = alltrue([for vm in var.virtual_machines : contains(["linux", "windows"], vm.os_type)])
    error_message = "Error: os_type can only be either \"linux\" or \"windows\" "
  }

  validation {
    condition     = alltrue([for vm in var.virtual_machines : contains(["Dynamic", "Static"], vm.private_ip_address_allocation)])
    error_message = "Error: private_ip_address_allocation can only be either \"Dymamic\" or \"Static\" "
  }

  validation {
    condition     = alltrue([for ip_index in [for vm in var.virtual_machines : vm.ip_index if vm.ip_index != null] : ip_index > 0])
    error_message = "Error: ip_index needs to be greater than 0"
  }

  validation {
    condition = alltrue([for vm in
      [for vm in var.virtual_machines : vm if vm.private_ip_address_allocation == "Static"] :
      (vm.ip_index != null && vm.private_ip_address == null) || (vm.ip_index == null && vm.private_ip_address != null)
    ])
    error_message = "Error: When private_ip_address_allocation = \"Static\" either ip_index or private_ip_address need to be specified per vm declaration"
  }

  validation {
    condition = alltrue([for vm in
      [for vm in var.virtual_machines : vm if vm.private_ip_address_allocation == "Dynamic"] :
      vm.ip_index == null && vm.private_ip_address == null
    ])
    error_message = "Error: either ip_index or private_ip_address can only be specified when private_ip_address_allocation = \"Static\" "
  }
}

variable "managed_disks" {
  description = "list of user managed disks configurations"
  type = list(object({
    name                 = string
    ud_resource_group    = string
    storage_account_type = optional(string, "Standard_LRS")
    create_option        = optional(string, "Empty")
    disk_size_gb         = optional(number, 20)
  }))
  default = []
}

variable "is_spoke" {
  description = "boolean flag to signal that this is a standard spoke build. If false, all resources are optional, and only what is explicitly defined by the user during module call is built. Defaults to true"
  type        = bool
  default     = true
}

# locals {
#   is_spoke = tobool(var.is_spoke) ## a control if we want to enforce disabling is_spoke based on another parameter
# }

variable "is_peered" {
  description = "boolean flag to peer spoke. Defaults to true"
  type        = bool
  default     = true
}

variable "random_kv_names" {
  description = "Keyvault names are randomized at creation. If false, uses the location code naming convention for backwards compatibility."
  type        = bool
  default     = false
}

variable "is_former_kv_naming_convention" {
  description = "boolean flag to signal whether this module call makes use of older key vault naming convention - to ensure backwards compatibility"
  type        = bool
  default     = false
}

variable "is_former_st_naming_convention" {
  description = "boolean flag to signal whether this module call makes use of older storage account naming convention - to ensure backwards compatibility"
  type        = bool
  default     = false
}

variable "is_former_log_analytics_workspace_naming_convention" {
  description = "boolean flag to signal whether this module call had created a log analytics workspace before they were fully treated as global and can only be built once per subscription"
  type        = bool
  default     = false
}

variable "deploy_diag_storage" {
  description = "boolean flag to signal that a customer managed boot diagnostics storage account should be built. Defaults to false"
  type        = bool
  default     = false
}

variable "container_registry" {
  description = "a list of azure container registry definitions"
  type = list(object({
    name                           = string
    admin_enabled                  = optional(bool, "false")
    subnet_name                    = optional(string)
    external_subnet_id             = optional(string)
    ud_mi_container_registry_admin = optional(list(string), [])
  }))
  default = []

  validation {
    condition     = alltrue([for acr in var.container_registry : acr.subnet_name != null || acr.external_subnet_id != null])
    error_message = "Error: Must declare either a subnet_name and or an external_subnet_id for each container registry."
  }

  validation {
    condition     = alltrue([for acr in var.container_registry : length(acr.name) > 0])
    error_message = "Error: Value must be provided for the name."
  }
}

variable "data_factory" {
  description = "Toggle creating a data factory and related resources."
  type = object({
    subnet_name        = optional(string)
    external_subnet_id = optional(string)
    ud_resource_group  = optional(string)
    legacy_adf         = optional(bool)
  })
  default = {}

  validation {
    condition = (
      alltrue([for value in values(var.data_factory) : value == null]) ||
      (try(var.data_factory.subnet_name, null) != null) ||
      (try(var.data_factory.external_subnet_id, null) != null)
    )
    error_message = "Error: Requires either a subnet_name or an external_subnet_id. "
  }
}


variable "log_analytics_workspace_id" {
  description = "Specifies the ID of a Log Analytics Workspace where Diagnostics Data should be sent."
  type        = string
  default     = null
}

variable "partner_solution_id" {
  description = "The ID of the market partner solution where Diagnostics Data should be sent."
  type        = string
  default     = null
}

variable "diag_storage_account_id" {
  description = "The ID of the Storage Account where logs should be sent."
  type        = string
  default     = null
}


variable "public_keyvaults" {
  description = "Enables public network access on keyvaults. Defaults to false to meet security requirements for new builds."
  type        = bool
  default     = false
}

variable "legacy_standard_kv" {
  description = "Flag for legacy builds to prevent recreation of keyvaults with non 'Premium' skus. Defaults to false."
  type        = bool
  default     = false
}

variable "is_hub" {
  description = "Disables pe subnet requirement, but preserve other is_spoke functionality. Defaults to false. Hub use only"
  type        = bool
  default     = false
}

variable "is_hub_staging" {
  description = "Prevents base keyvault and eventhub related resources from being built. Defaults to false. Hub use only"
  type        = bool
  default     = false
}

locals {
  validate_pe_subnet = (var.is_spoke == true && (var.is_host == false && local.build_base_resources) && var.public_keyvaults == false && length([for subnet in local.all_subnets : subnet.name if subnet.type == "pe"]) != 1) ? tobool("${local.ec_error_aheader} ${local.ec_error_pe1} ${local.ec_error_pe2} ${local.ec_error_pe3} ${local.ec_error_zfooter}") : true
}

variable "snow_dns_env" {
  description = "Sets the ServiceNow environment to make DNS requests to. Defaults to Dev." #Change to Prod for release
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "qa", "prod"], lower(var.snow_dns_env))
    error_message = "snow_dns_env must be one of the following: dev, qa, prod"
  }
}

variable "flowlog_retention_days" {
  description = "Days to set network watcher flow log retention to. Default is zero (forever)."
  type        = number
  default     = 0
}
variable "app_insights" {
  description = "a list of user-defined app insights objects"
  type = list(object({
    name                 = string
    ud_resource_group    = string
    application_type     = string
    daily_data_cap_in_gb = optional(string)
    retention_in_days    = optional(number, 90)
  }))
  default = []
  validation {
    condition = alltrue([
      for app_insight in var.app_insights : contains(["ios", "java", "MobileCenter", "Node.JS", "other", "phone", "store", "web"], app_insight.application_type)
    ])
    error_message = "Error: application_type must be one of the following values: ios, java, MobileCenter, Node.JS, other, phone, store, web."
  }

  validation {
    condition = alltrue([
      for app_insight in var.app_insights : contains([30, 60, 90, 120, 180, 270, 365, 550, 730], app_insight.retention_in_days)
    ])
    error_message = "Error: retention_in_days must be the follwoing 30, 60, 90, 120, 180, 270, 365, 550 or 730."
  }
}

variable "web_apps" {
  type = list(object({
    name                              = string
    ud_app_service_plan               = string
    subnet_name                       = optional(string)
    external_subnet_id                = optional(string)
    site_config                       = optional(any, {})
    ud_resource_group                 = optional(string)
    integrated_subnet_name            = optional(string)
    external_integrated_subnet_id     = optional(string)
    app_settings                      = optional(map(string))
    application_type                  = optional(string, "web")
    app_insights_daily_data_cap_in_gb = optional(string)
    app_insights_retention_in_days    = optional(number, 90)
    ud_user_identity                  = optional(string)
    user_identity_name                = optional(string)
    user_identity_resource_group      = optional(string)
    disable_vnet_integration          = optional(bool, false)
    public_network_access_enabled     = optional(bool, false) # optional flag, false by default
    ase_integration                   = optional(bool, false) # Indicator of ASE integration requirement
  }))

  default = []

  validation {
    condition = alltrue([
      for app in var.web_apps :
      app.ase_integration != true ? (app.integrated_subnet_name != null || app.external_integrated_subnet_id != null) : true
    ])
    error_message = "For web apps not deployed into an ASE, either integrated_subnet_name or external_integrated_subnet_id must be provided."
  }

#  validation {
#    condition     = alltrue([for app in var.web_apps : app.integrated_subnet_name != null || app.external_integrated_subnet_id != null || app.disable_vnet_integration])
#    error_message = "The web app does not have external_integrated_subnet_id or integrated_subnet_name. If you want to leave these values blank and use a non-security compliant version, set disable_vnet_integration to true."
#  }

  validation {
    condition     = alltrue([for app in var.web_apps : app.user_identity_name != null ? app.user_identity_resource_group != null : true])
    error_message = "When using `user_identity_name`, `user_identity_resource_group` must be provided."
  }
}


variable "monitor_action_groups" {
  type = list(object({
    name              = string
    email_receiver    = map(string)
    ud_resource_group = string
  }))
  default = []
}

variable "forward_law_to_eh" {
  description = "This will send the diagnostics of the log analytics workspace to event hub for splunk."
  type        = bool
  default     = true
}

variable "api_management" {
  description = "a list of azure apim management definitions"
  type = list(object({
    name                  = string
    ud_resource_group     = string
    publisher_name        = string
    publisher_email       = string
    external_subnet_id    = optional(string)
    sku_name              = optional(string, "Developer")
    deployed_units        = optional(number, 1)
    subnet_name           = optional(string)
    virtual_network_type  = optional(string, "Internal")
    kv_external_subnet_id = optional(string, null)
    kv_subnet_name        = optional(string)
    public_ip_address_id  = optional(bool, false)
    is_stv2               = optional(bool, false)
    pip_allocation_method = optional(string, "Static")
    pip_sku               = optional(string, "Standard")
    zones                 = optional(list(string), [])
    additional_location   = optional(object({
      location             = string
      capacity             = number
      zones                = list(string)
      gateway_disabled     = bool
      virtual_network_type = string
      external_subnet_id   = string 
    }))
  }))
  default = []

  validation {
    condition = alltrue([
      for apim in var.api_management : contains(["Developer", "Premium", "Isolated"], apim.sku_name)
    ])
    error_message = "Error: sku_name must be one of the following values: Developer, Isolated, Premium."
  }

  validation {
    condition = alltrue([
      for apim in var.api_management : contains([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], apim.deployed_units)
    ])
    error_message = "Error: Deployed units must be between 1 and 12."
  }

  validation {
    condition = alltrue([
      for apim in var.api_management : contains(["Internal", "None", "pe"], apim.virtual_network_type)
    ])
    error_message = "Error: Virtual network type must be either Internal, None, or pe."
  }

  validation {
    condition = alltrue([
      for apim in var.api_management : apim.subnet_name != null || apim.external_subnet_id != null
    ])
    error_message = "Error: a subnet_name or external_subnet_id must be provided."
  }

  validation {
    condition = alltrue([
      for apim in var.api_management : apim.kv_subnet_name != null || apim.kv_external_subnet_id != null
    ])
    error_message = "Error: a kv_subnet_name or kv_external_subnet_id must be provided."
  }

  validation {
    condition = alltrue([
      for apim in var.api_management : contains(["Static", "Dynamic"], apim.pip_allocation_method)
    ])
    error_message = "Error: pip_allocation_method must be Static or Dynamic"
  }

  validation {
    condition = alltrue([
      for apim in var.api_management : contains(["Standard", "Basic"], apim.pip_sku)
    ])
    error_message = "Error: pip_sku must be Standard or Basic"
  }

  validation {
    condition     = length(var.api_management) <= 1
    error_message = "Error: only one object is supported for api_management"
  }
}

variable "databricks" {
  description = "a list of user-defined databricks objects"
  type = list(object({
    name                            = string
    ud_resource_group               = string
    sku                             = optional(string, "premium")
    storage_account_sku_name        = optional(string, "Standard_LRS")
    public_subnet_name              = string
    private_subnet_name             = string
    pe_subnet_name                  = optional(string)
    external_subnet_id              = optional(string)
    pe_subresources                 = optional(list(string), ["databricks_ui_api"])
    import_dbk                      = optional(bool, false)
    import_dbk_name                 = optional(string)
    import_dbk_storage_account_name = optional(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for dbw in var.databricks : contains(["standard", "premium", "trial"], dbw.sku)
    ])
    error_message = "Error: invalid SKU. Must be one of the following: \"standard\", \"premium\", or \"trial\"."
  }
  validation {
    condition = alltrue([
      for dbw in var.databricks : contains(["Standard_LRS", "Standard_GRS", "Standard_RAGRS", "Standard_ZRS", "Standard_GZRS", "Standard_RAGZRS", "Premium_LRS", "Premium_GRS", "Premium_RAGRS", "Premium_ZRS", "Premium_GZRS", "Premium_RAGZRS"], dbw.storage_account_sku_name)
    ])
    error_message = "Error: invalid Storage Account SKU. Must be one of the following: \"Standard_LRS\", \"Standard_GRS\", \"Standard_RAGRS\", \"Standard_ZRS\", \"Standard_GZRS\", \"Standard_RAGZRS\", \"Premium_LRS\", \"Premium_GRS\", \"Premium_RAGRS\", \"Premium_ZRS\", \"Premium_GZRS\", \"Premium_RAGZRS\"."
  }
  validation {
    condition     = alltrue([for dbw in var.databricks : dbw.import_dbk == true ? dbw.import_dbk_name != null && dbw.import_dbk_storage_account_name != null : true])
    error_message = "The databricks instance must be provided with a import_dbk_name and import_dbk_storage_account_name."
  }
}
variable "recovery_services_vaults" {
  description = "a list of azure recovery services vault definitions"
  type = list(object({
    name                         = string
    subnet_name                  = string
    storage_mode_type            = optional(string, "GeoRedundant")
    immutability                 = optional(string, "Disabled")
    cross_region_restore_enabled = optional(bool, false)
  }))
  default = []

  validation {
    condition = alltrue([
      for rsv in var.recovery_services_vaults : contains(["GeoRedundant", "LocallyRedundant", "ZoneRedundant"], rsv.storage_mode_type)
    ])
    error_message = "Error: invalid storage_mode_type entered. Must be one of the following: \"GeoRedundant\", \"LocallyRedundant\", or \"ZoneRedundant\"."
  }

  validation {
    condition = alltrue([
      for rsv in var.recovery_services_vaults : contains(["Locked", "Unlocked", "Disabled"], rsv.immutability)
    ])
    error_message = "Error: invalid storage_mode_type entered. Must be one of the following: \"Locked\", \"Unlocked\", or \"Disabled\"."
  }
  validation {
    condition = alltrue([
      for rsv in var.recovery_services_vaults : contains(["GeoRedundant"], rsv.storage_mode_type) if rsv.cross_region_restore_enabled != false
    ])
    error_message = "Error: When cross_region_restore_enabled is set to true, storage_mode_type must be set to \"GeoRedundant\"."
  }
}
variable "load_balancers" {
  description = "a list of load balancer configurations"
  type = list(object({
    name                          = string
    sku                   = optional(string, "Standard")
    ud_resource_group             = string
    frontend_ip_config =object({
      name    = optional(string)
      subnet = optional(string)
      is_dynamic_ip = optional(bool)
      #ip_allocation_type = optional(string)
      ip_address = optional(string)
    })
    backend_pool = object({
      #name    = optional(string)
      #configuration     = optional(string, "IP_Address")
      ip_addresses = list(string)


    })
    health_probes = list(object({
        name = optional(string)
        port = optional(number)
        protocol = optional(string, "Tcp")
        probe_threshold = optional(number, 5)
        interval = optional(number, 5)
    }))
    lb_rules = list(object({
      name = optional(string)
      frontend_port = optional(number)
      backend_port = optional(number)
      health_probe = optional(string)
      frontend_config_name = optional(string)
      protocol = optional(string, "Tcp")
      backend_pool_names = optional(list(string))
    }))
  }))
  default = []


  #validation {
  #  condition     = alltrue([for lb in var.load_balancers : contains(["internal", "public"], lb.type)])
  #  error_message = "Error: load balancer type can only be either \"internal\" or \"public\" "
  ##}

  validation {
    condition     = alltrue([for lb in var.load_balancers : contains(["Standard", "Gateway"], lb.sku)])
    error_message = "Error: sku can only be either \"Standard\" or \"Gateway\" "
  }
  #validation {
  #  condition     = alltrue([for lb in var.load_balancers : contains(["NIC", "IP_Address"], lb.backend_pool.configuration)])
  #  error_message = "Error: configuration can only be either \"NIC\" or \"IP_address\" "
  #}
  #validation {
  #  condition     = alltrue([for lb in var.load_balancers : lb.frontend_ip_config.is_dynamic_ip == false && lb.frontend_ip_config.ip_address == null])
  #  error_message = "Error: If is_dynamic_ip is set to false an ip_address must be provided. "
  #}

}

variable "ase_internal_encryption" {
  type        = bool
  description = "Enable internal encryption on ASE or not"
  default     = false
}