locals {
  ec_error_aheader = "                           ========EXPRESSCLOUD VALIDATION ERROR========                                 "
  ec_error_zfooter = "                           =====END OF EXPRESSCLOUD VALIDATION ERROR====                                 "

  ec_error_pe1 = "   Type 'pe' subnet is automatically created when using Automatic IPAM and only and exactly 1 subnet can have type pe.   "
  ec_error_pe2 = " The usage of this type is now restricted to vnet_cidr spokes only. To proceed, remove this type if not using vnet_cidr. "
  ec_error_pe3 = "        If specifying vnet_cidr, please, ensure that you have 1 and only 1 subnet with type = 'pe', to proceed           "

  ec_error_psql_subnet = "  The delegated_subnet_name provided for a Postgres Flexible Server must be a delegated subnet defined in the 'subnets' variable with type 'psql_flexserver'.  "

  ec_error_nsg_name1 = "      The nsg rule name must begin with a letter or number, end with a letter, number or underscore,     "
  ec_error_nsg_name2 = "               and may contain only letters, numbers, underscores, periods, or hyphens.                  "

  ec_error_nsg_addresses               = "                         One of the addresses in the given list is invalid                               "
  ec_error_nsg_address                 = "                                  The provided address is invalid                                        "
  ec_error_i_sku_names_app_env_subnets = "    This combination of app service plan 'sku' and 'subnet_name' specified is invalid.  When specifying 'sku' as one of the following: 'I1', 'I2', 'I3', 'I1v2', 'I2v2', 'I3v2', 'I4v2', 'I5v2', 'I6v2' , the subnet 'type' need to be 'app_service_env'"

  ec_error_cog_no_se = "The listed subnet does not have Microsoft.CognitiveServices service endpoints. Please add type='cog' to this subnet. "

  ec_error_not_exist = "One or more resource you are attempting to create a private endpoint for does not exist.  "

  ec_error_conflict_priorities  = "    Rules have conflicting priority values. Rules with the same direction must have unique priorities.   "
  ec_error_conflict_priorities2 = "        Update nsg_rules.csv with new priorities. See below for conflicting rules.      "

  ec_error_subnet_types = "Error: Unsupported subnet type. The following subnet types are currently supported: none, aks, app_service_env, cog, pe, vm-win-aeth, vm-win-corp, vm-linux-aeth, vm-linux-corp, apim, databricks, ${local.db_subnet_types_str}."

  ec_error_subnet_type = "         The specified subnet type is not of type 'aks'. Please make sure you're using a subnet with type 'aks'         "
  ec_error_subnet_name = "                   The aks subnet_name does not match any of the specified subnets.                   "

  ec_error_custom_key_vault = "The 90 days soft delete custom key vault is missing, create a PR for the host file to create the missing key."
  ec_error_cross_region_key_vault = "The base key vault in the cross region is missing the 'base = true' tag."
  ec_error_cross_region_custom_key_vault_single = "The 90 days soft delete custom key vault is missing in the cross region, Add this variable 'build_custom_key_vault = true' in the cross region spoke file."
  ec_error_cross_region_custom_key_vault_shared = "The 90 days soft delete custom key vault is missing in the cross region, create a PR for the cross region host file with host_index = 0 to create the missing key."
}

# resource "null_resource" "dr_tier_required" {
#  count = var.environment == "prod" ? 1 : 0
#   lifecycle {
#     precondition {
#       condition = var.environment == "prod" && var.dr_tier != null
#       error_message = "When defining a prod environment, you must add a DR Tier using the \"dr_tier\" variable. Valid values are [\"1A\",\"1B\",\"1C\",\"1D\",\"1E\",\"2A\",\"2B\",\"2C\",\"2D\",\"2E\",\"3A\",\"3B\",\"3C\",\"3D\",\"3E\",\"4A\",\"4B\",\"4C\",\"4D\",\"4E\",\"5A\",\"5B\",\"5C\",\"5D\",\"5E\",\"9Z\"] "
#     }

#   }

# }
