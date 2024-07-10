data "azurerm_subscription" "hub" {
  provider = azurerm.hub
}

locals {

  name_prefix                    = var.is_host ? "${local.host_name_prefix}" : "${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}"
  cross_region_spoke_name_prefix = "${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_cross_location_name}"

  env_suffix = lower(var.required_tags.environmenttype) == lower("DR") ? "prod" : lower(var.required_tags.environmenttype)

  subscription_name_no_env = trimsuffix(
    trimsuffix(
      replace(
        trimsuffix(
          lower("${data.azurerm_subscription.current.display_name}"),
          lower("-${local.env_suffix}")
        ),
        " ",
      ""),
    "non-production"),
  "production")


  host_name_prefix              = var.host_prefix != null ? lower(var.host_prefix) : lower("${local.subscription_name_no_env}-${local.env_suffix}-${local.short_location_name}")
  cross_region_host_name_prefix = var.host_prefix != null ? lower(var.host_prefix) : lower("${local.subscription_name_no_env}-${local.env_suffix}-${local.short_cross_location_name}")

  host_rg_suffix = var.host_index != 0 ? "${var.host_index}" : ""
  host_cross_region_rg_suffix = var.cross_region_host_index != 0 ? "${var.cross_region_host_index}" : ""

  vnet_name    = local.network_strategy == "shared_vnet" ? local.host_vnet_name : var.is_host == true ? "vnet-${local.host_name_prefix}" : "vnet-${local.name_prefix}"
  vnet_rg_name = local.network_strategy == "shared_vnet" ? local.host_vnet_rg_name : length(azurerm_resource_group.network_rg) > 0 ? azurerm_resource_group.network_rg[0].name : null
  vnet_id      = local.host_vnet_id != null ? local.host_vnet_id : length(azurerm_virtual_network.vnet) > 0 ? azurerm_virtual_network.vnet[0].id : null

  is_client = tobool(local.network_strategy == "shared_vnet" && !var.is_host)

  host_tag = var.is_host ? { "host" : "true" } : {}
  all_tags = merge(var.required_tags, var.optional_tags, local.host_tag, local.dr_tier_tag, { "managedby" = "ExpressCloud" })

  base_kv                          = local.is_client ? data.azurerm_key_vault.host_base_kv[0] : var.is_spoke ? azurerm_key_vault.base_kv[0] : null
  base_kv_id                       = local.is_client ? data.azurerm_resources.host_base_key_vault[0].resources[0].id : var.is_spoke ? azurerm_key_vault.base_kv[0].id : null
  base_key_id                      = var.is_spoke ? azurerm_key_vault_key.base_kv_key[0].id : null
  #variables to get cross region key and umi
  cross_region_base_key_vault      = local.is_client || var.is_spoke ? (length(data.azurerm_resources.cross_region_base_key_vault) > 0 ? data.azurerm_resources.cross_region_base_key_vault[0].resources[0] : null) : null
  cross_region_base_key_vault_id   = local.cross_region_base_key_vault != null ? local.cross_region_base_key_vault.id : null
  cross_region_base_key_vault_name = local.cross_region_base_key_vault != null ? local.cross_region_base_key_vault.name : null
  cross_region_base_key_id         = local.cross_region_base_key_vault != null ? (length(data.azurerm_key_vault_key.cross_region_base_key) > 0 ? data.azurerm_key_vault_key.cross_region_base_key[0].id : null) : null
  cross_region_user_managed_id     = local.is_client || var.is_spoke ? (length(data.azurerm_resources.cross_region_base_kv_uai) > 0 ? data.azurerm_resources.cross_region_base_kv_uai[0].resources[0].id : null) : null
  #resource group name for host file if shared_vnet is used and for spoke file in case of single tenant
  cross_region_base_kv_rg_id       = local.is_client ? "rg-${local.cross_region_host_name_prefix}-secr${local.host_cross_region_rg_suffix}" : var.is_spoke ? "rg-${local.cross_region_spoke_name_prefix}-secr" : null
  #variable to check if custom key vault is needed if base key vault is not 90 days
  need_custom_key_vault               = local.base_kv != null? (lookup(local.base_kv.tags, "soft-delete", null) == "90" ? false : true) : false
  #build_custom_key_vault var used for cross region spoke files in case it has no servers on it that require 90 days but needed for grb
  #db_use_custom_key_vault var is to check if this db type has custom key flag enabled and if there are servers defined in spoke file
  #this var is to return if we need to create a custom key vault(if it is a host or single tenant having servers defined in spoke file which requires custom key and base key vault is not 90 days)
  use_custom_key_vault                = (var.build_custom_key_vault || local.db_use_custom_key_vault || var.is_host) && local.need_custom_key_vault
  use_custom_cross_region_key_vault   = (local.db_use_custom_key_vault && length(local.db_grb_list) > 0 ) && length (data.azurerm_key_vault.cross_region_base_kv)>0 ? (lookup(data.azurerm_key_vault.cross_region_base_kv[0].tags, "soft-delete", null) == "90" ? false : true) : false
  #primary key id, umi and cross region key id for handling databases that use custom key vaults
  #in case of custom key is needed and shared vnet then get host custom key id, in case of single tenant then get custom key of spoke file, in case of no need for custom key then use base key id of spoke file
  db_base_key_id                      = (local.db_use_custom_key_vault && local.need_custom_key_vault)? azurerm_key_vault_key.base_custom_kv_key[0].id : local.base_key_id
  custom_base_key_vault_id            = local.use_custom_key_vault ? local.is_client ? data.azurerm_resources.host_custom_key_vault[0].resources[0].id : azurerm_key_vault.base_custom_kv[0].id : null
  base_key_vault_umi                  = var.is_spoke ? azurerm_user_assigned_identity.base_kv_uai[0].id : null
  #in case of custom key is needed then get cross region custom key else use cross region base key
  db_cross_region_key_id              = local.use_custom_cross_region_key_vault? data.azurerm_key_vault_key.cross_region_cutom_base_key[0].id : local.cross_region_base_key_id
  
  build_base_resources = local.network_strategy == "shared_vnet" ? (local.is_client ? var.build_base_resources : true) : true
  environment_type = contains(["prod", "dr"], var.environment) ? "prod" : "nonprod"

  enforce_prod_envs = [] #add regions to prevent nonprod hub use

  legacy_hub_subscription_ids = ["59b2cd00-9406-4a41-a772-e073dbe19796","29ea5d6f-8539-4a95-8198-ca801994cbdb"]  #CVS-SECUREHUB000, #CVS-SECUREHUB001

  uses_legacy_hub = contains(local.legacy_hub_subscription_ids,data.azurerm_subscription.hub.subscription_id)

  routing_environment = var.routing_environment == "prod" || contains(local.enforce_prod_envs, var.location) || local.uses_legacy_hub ? "prod" : local.environment_type

  region_environment = lower("${var.location}_${local.routing_environment}")
  # enforces prod when not using static routes to preserve existing nonprod spokes

    routing_strategy = local.uses_legacy_hub ? "bgp" : "static"

    dr_tier_tag = var.dr_tier != null ? { dr_tier = upper(var.dr_tier) } : {}

}

