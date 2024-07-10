locals {
  rg_name_prefix = lower("rg-${local.name_prefix}")
  rg_suffix      = var.is_host ? local.host_rg_suffix : ""
}

resource "azurerm_resource_group" "backup_rg" {
  count = var.is_spoke ? 1 : 0

  name     = "${local.rg_name_prefix}-bkp${local.rg_suffix}"
  location = var.location
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  tags = local.all_tags
}

resource "azurerm_resource_group" "adf_rg" {
  count    = anytrue([for value in values(var.data_factory) : value != null]) && lookup(var.data_factory, "ud_resource_group", null) == null ? 1 : 0
  name     = "${local.rg_name_prefix}-adf${local.rg_suffix}"
  location = var.location
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  tags = local.all_tags
}

resource "azurerm_resource_group" "ud_rgs" {
  for_each = { for ud_rg in var.resource_groups : ud_rg => lower(ud_rg) }
  name     = "${local.rg_name_prefix}-${each.value}${local.rg_suffix}"
  location = var.location
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  tags = local.all_tags
}

resource "azurerm_resource_group" "app_services_rg" {
  count    = length([for subnet in local.subnets_with_delegation_info : subnet if subnet.type == "app_service_env"]) + length([for app_info in var.app_service_plans : app_info]) > 0 ? 1 : 0
  name     = "${local.rg_name_prefix}-aas${local.rg_suffix}"
  location = var.location
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  tags = local.all_tags
}

resource "azurerm_resource_group" "cog_rg" {
  count    = (length(var.cognitive_services) > 0) && (anytrue([for cog in var.cognitive_services : cog.ud_resource_group == null])) ? 1 : 0
  name     = "${local.rg_name_prefix}-cog${local.rg_suffix}"
  location = var.location
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  tags = local.all_tags
}

resource "azurerm_resource_group" "aks_rg" {
  count = local.aks_subnet_name != null ? 1 : 0

  name     = "${local.rg_name_prefix}-aks${local.rg_suffix}"
  location = var.location
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  tags = local.all_tags
}

resource "azurerm_resource_group" "sb_rg" {
  count = length(var.service_bus_namespace) > 0 ? 1 : 0

  name     = "${local.rg_name_prefix}-sb${local.rg_suffix}"
  location = var.location
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  tags = local.all_tags
}

resource "azurerm_resource_group" "network_rg" {
  count = length(local.vnet_cidr) > 0 || (length(local.all_subnets) > 0 && local.network_strategy == "classic") || var.is_host ? 1 : 0

  name     = "${local.rg_name_prefix}-ntwk${local.rg_suffix}"
  location = var.location
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  tags = local.all_tags
}
resource "azurerm_resource_group" "diag_rg" {
  count = var.is_spoke && var.deploy_diag_storage ? 1 : 0

  name     = "${local.rg_name_prefix}-diag${local.rg_suffix}"
  location = var.location
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  tags = local.all_tags
}
resource "azurerm_resource_group" "secr_rg" {
  count = var.is_spoke || var.log_analytics_workspace != "none" ? 1 : 0

  name     = "${local.rg_name_prefix}-secr${local.rg_suffix}"
  location = var.location
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  tags = local.all_tags
}

resource "azurerm_resource_group" "srch_rg" {
  count = (length(var.search_services) > 0) && (anytrue([for srch in var.search_services : srch.ud_resource_group == null])) ? 1 : 0

  name     = "${local.rg_name_prefix}-srch${local.rg_suffix}"
  location = var.location
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  tags = local.all_tags
}

resource "azurerm_resource_group" "mi_rg" {
  count = length([for ud_mi in var.ud_managed_identities : ud_mi if ud_mi.resource_group_name == null && ud_mi.resource_group == null]) > 0 ? 1 : 0

  location = var.location
  name     = "${local.rg_name_prefix}-mi${local.rg_suffix}"

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_resource_group" "acr_rg" {
  count = length(var.container_registry) > 0 ? 1 : 0

  name     = "${local.rg_name_prefix}-acr${local.rg_suffix}"
  location = var.location
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  tags = local.all_tags
}

resource "azurerm_resource_group" "db_rg" {
  count    = (!contains(var.resource_groups, "db") && length(var.psqls) > 0) ? 1 : 0
  name     = "${local.rg_name_prefix}-db${local.rg_suffix}"
  location = var.location
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  tags = local.all_tags
}

resource "azurerm_resource_group" "db_rgs" {
  for_each = { 
    for key, db_rg in local.db_rg_list : key => db_rg if (!contains(var.resource_groups, db_rg.resource_group.rg_suffix) && length(db_rg.db_list)>0) 
  }

  name     = "${local.rg_name_prefix}-${each.value.resource_group.rg_suffix}${local.rg_suffix}"
  location = var.location
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  tags = local.all_tags
}

locals {
  all_rgs = concat(
    azurerm_resource_group.backup_rg,
    azurerm_resource_group.adf_rg,
    [for ud_name, ud_rg in azurerm_resource_group.ud_rgs : ud_rg],
    azurerm_resource_group.app_services_rg,
    azurerm_resource_group.cog_rg,
    azurerm_resource_group.aks_rg,
    azurerm_resource_group.sb_rg,
    azurerm_resource_group.network_rg,
    azurerm_resource_group.diag_rg,
    azurerm_resource_group.secr_rg,
    azurerm_resource_group.srch_rg,
    azurerm_resource_group.mi_rg,
    azurerm_resource_group.acr_rg,
    azurerm_resource_group.db_rg,
    [for db_name, db_rg in azurerm_resource_group.db_rgs : db_rg],
  )
  all_rg_reader_assignments = flatten([for group in var.reader_groups : [for rg in local.all_rgs : {
    rg_id    = rg.id
    rg_name  = rg.name
    ad_group = group
    }
  ]])
}

resource "azurerm_role_assignment" "rg_reader_permissions" {
  for_each = { for permission in local.all_rg_reader_assignments : "${permission.rg_name}.${permission.ad_group}" => permission }

  scope                = each.value.rg_id
  role_definition_name = "Reader"
  principal_id         = each.value.ad_group
}



