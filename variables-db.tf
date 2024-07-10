locals{
  automation_spn = {
    display_name = "SP-ECE-AUTOMATION"
    object_id    = "5b73d199-58a8-43a1-8926-c03b04b9c24f"
  }
  
is_prod_env = contains(["prod", "pt", "preprod"], var.environment)
  
##########################################################################
# Reusable components configuration
##########################################################################

  #used for configuring different DB resources
  db_types = {
    "psql" = {
      db_list       = var.psqls
      grb_enabled   = true
      # resource_group={
      #   rg_suffix     = "db"
      # }
      subnet = {
        type   = "psql_flexserver"
        size   = "28"
        delegation_key = {
          delegation_name            = "Microsoft.DBforPostgreSQL/flexibleServers"
          service_delegation_name    = "Microsoft.DBforPostgreSQL/flexibleServers"
          service_delegation_actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
        }
      }
      nsg = {
        port_num = "5432"
        file_name = "psql_nsg_rules.csv"
        rule_priority_from = "4030"
        rule_priority_to = "4039"
        aseaks_rule_priority = "4039"
        aseaks_outbound_rule_name = "AllowPostgresTrafficFromASEAKSOutbound"
        aseaks_inbound_rule_name = "AllowPostgresTrafficFromASEAKSInbound"
      }
    }
  }
  
  #used for creating database resource group 'db_rg' in resource-groups.tf file
  # db_rg_list = [for db_type in local.db_types : db_type if (db_type.resource_group!= null && !contains(var.resource_groups, db_type.resource_group.rg_suffix) && length(db_type.db_list)>0)]
  db_rg_list = {for key, db_type in local.db_types : key=> db_type if try(db_type.resource_group, null)!= null}
  
  #used for creating nsg rules in network-security-groups.tf file
  db_nsg_list = {for key, db_type in local.db_types: key => db_type if try(db_type.nsg, null)!= null}
  
  #used for validation of subnet types
  db_delegated_subnets_list = [for db_type in local.db_types : db_type.subnet if try(db_type.subnet, null)!= null && try(db_type.subnet.delegation_key, null)!= null]

  #used for validation of subnet types
  db_subnets_list = {for key, db_type in local.db_types : key => db_type.subnet if try(db_type.subnet, null)!= null}
  db_subnet_types_list = [for db_type in local.db_types : db_type.subnet.type if try(db_type.subnet, null)!= null]
  db_subnet_types_str = join(", ", local.db_subnet_types_list)

  #used for cross region key vault for grb
  db_grb_list = {for key, db_type in local.db_types : key=> db_type if (try(db_type.grb_enabled, null) ==true && length(db_type.db_list) >0 && (local.is_prod_env == true || length([for db in db_type.db_list : db.name if try(db.grb_nonprod_requested, null) == true]) >0)) && (length([for db in db_type.db_list : db.name if try(db.geo_backup_key_vault_key_id, null) == null]) >0)}

  #used for automated custom key vaults
  db_use_custom_key_vault = length([for db_type in local.db_types : true if(try(db_type.use_custom_key_vault, null) == true && length(db_type.db_list) > 0) ]) >0
}
##########################################################################
# PSQLS variables
##########################################################################
variable "psqls" {
  type = list(object({
    name                                 = string
    delegated_subnet_name                = string
    version                              = string
    ud_resource_group                    = optional(string)    
    storage_mb                           = optional(string)
    create_mode                          = optional(string)
    source_server_id                     = optional(string)
    point_in_time_restore_time_in_utc    = optional(string)
    geo_backup_key_vault_key_id          = optional(string)
    geo_backup_user_assigned_identity_id = optional(string)   
    test_mode                            = optional(bool, false)
    grb_nonprod_requested                = optional(bool, false)
    ha_enabled                           = optional(bool, false) 
    auto_grow_enabled                    = optional(bool, false)
    dbaas_standard_size                  = optional(string, "small")

    maintenance_window   = optional(object({
      maintenance_day    = number
      maintenance_hour   = number
      maintenance_minute = number
      }), {
      maintenance_day    = 6  # Saturday
      maintenance_hour   = 7  # 7:00 AM
      maintenance_minute = 0  # On the hour
    })
    }),
  )
  default = []

  validation {
    condition = alltrue([
      for psql in var.psqls : contains(["xsmall", "small", "medium", "large"], psql.dbaas_standard_size)
    ])
    error_message = "Error: dbaas_standard_size must be one of the following values: xsmall, small, medium, large."
  }

  validation {
    condition = alltrue([
      for psql in var.psqls : contains(["13", "14", "15"], psql.version)
    ])
    error_message = "Error: version must be one of the following values: 13, 14, 15."
  }

  validation {
    condition = alltrue([
      for psql in var.psqls : contains([32768, 65536, 131072, 262144, 524288, 1048576, 2097152, 4194304, 8388608, 16777216], tonumber(psql.storage_mb)) if psql.storage_mb != null
    ])
    error_message = "Error: storage_mb must be one of the following values: null, 32768, 65536, 131072, 262144, 524288, 1048576, 2097152, 4194304, 8388608, 16777216."
  }

  validation {
    condition = alltrue([
      for psql in var.psqls : (psql.source_server_id != null && psql.point_in_time_restore_time_in_utc != null) if psql.create_mode == "PointInTimeRestore"
    ])
    error_message = "Error: a source_server_id and point_in_time must be provided when doing a point in time restore."
  }

  validation {
    condition = alltrue([
      for psql in var.psqls : contains(["Default", "Update", "PointInTimeRestore", "Replica"], psql.create_mode) if psql.create_mode != null
    ])
    error_message = "Error: when create_mode is set, it must be one of the following values: Default, Update, PointInTimeRestore, Replica"
  }

  validation {
    condition = alltrue([
      for psql in var.psqls : (psql.maintenance_window.maintenance_day >= 0 && psql.maintenance_window.maintenance_day <= 6) if psql.maintenance_window != null
    ])
    error_message = "Error: when maintenance_day is set, it must be a number, 0-6, to indicate day of week for maintenance window, where the week starts on a Sunday, i.e. Sunday = 0, Monday = 1. Defaults to 6."
  }

  validation {
    condition = alltrue([
      for psql in var.psqls : (psql.maintenance_window.maintenance_hour >= 0 && psql.maintenance_window.maintenance_hour <= 23) if psql.maintenance_window != null
    ])
    error_message = "Error: when maintenance_hour is set, it must be a number relating to the 24-hr clock, 0-23, UTC Zone. i.e. 7 means 7:00AM UTC, 20 is 20:00PM UTC. Defaults to 7."
  }

  validation {
    condition = alltrue([
      for psql in var.psqls : (psql.maintenance_window.maintenance_minute >= 0 && psql.maintenance_window.maintenance_minute <= 59) if psql.maintenance_window != null
    ])
    error_message = "Error: when maintenance_minute is set, it must be a number from 0-59. Defaults to 0."
  }

}

locals {
  psql_subnet_names                 = [for subnet in var.subnets : subnet.name if subnet.type == "psql_flexserver"]
  psqls_with_delegated_subnets      = [for psql in var.psqls : psql if contains(local.psql_subnet_names, psql.delegated_subnet_name)]
  validate_psqls_subnet             = length(local.psqls_with_delegated_subnets) == length(var.psqls) ? true : tobool("${local.ec_error_aheader} ${local.ec_error_psql_subnet} ${local.ec_error_zfooter}")
}

variable "psqls_databases" {
  type = list(object({
    psql_name              = string
    db_name                = string
    db_env                 = optional(string)
    collation              = optional(string, "en_US.utf8")
    charset                = optional(string, "utf8")
    ddl_user_defined_mi    = optional(list(string), [])
    dml_user_defined_mi    = optional(list(string), [])
    read_only_ad_group_ids = optional(list(string), [])
    extensions             = optional(list(string), [])  
  }))
  default = []

  validation {
    condition = alltrue([
      for db in var.psqls_databases : contains(["dev", "qa", "uat", "stg", "stress", "pt", "prod", "nonprod", "preprod", "poc"], db.db_env)
    ])
    error_message = "Error: environment needs to be one of the following: [ dev | qa | uat | stg | stress | pt | prod | nonprod | preprod | poc ]"
  }

}