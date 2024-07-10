resource "random_password" "password_psql_flex" {
  count            = length(var.psqls) > 0 ? 1 : 0
  length           = 128
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

locals {
  dbaas_sizing_map = {
    "xsmall" = {
      sku_name   = "GP_Standard_D2ds_v4"
      storage_mb = "32768"
    }
    "small" = {
      sku_name   = "GP_Standard_D4ds_v4"
      storage_mb = "32768"
    }
    "medium" = {
      sku_name   = "GP_Standard_D16ds_v4"
      storage_mb = "131072"
    }
    "large" = {
      sku_name   = "GP_Standard_D64ds_v4"
      storage_mb = "524288"
    }
  }

  subscription_name_suffix = replace(lower(trimprefix(data.azurerm_subscription.current.display_name, "SUB-")), " ", "-")

  psql_flex_db_ddl_ud_mi_users = flatten([
    for database in var.psqls_databases : [
      for identity_name in database.ddl_user_defined_mi : {
        name                    = "psql_flex_db_ddl_ud_mi_user_${database.db_name}_${database.db_env}_${identity_name}"
        ud_mi_name              = identity_name
        psql_flex_database_name = database.db_name
        psql_flex_database_env  = database.db_env
        psql_flex_server_name   = database.psql_name
      }
    ]
  ])

  psql_flex_db_dml_ud_mi_users = flatten([
    for database in var.psqls_databases : [
      for identity_name in database.dml_user_defined_mi : {
        name                    = "psql_flex_db_dml_ud_mi_user_${database.db_name}_${database.db_env}_${identity_name}"
        ud_mi_name              = identity_name
        psql_flex_database_name = database.db_name
        psql_flex_database_env  = database.db_env
        psql_flex_server_name   = database.psql_name
      }
    ]
  ])

  psql_flex_db_read_only_groups = flatten([
    for database in var.psqls_databases : [
      for ad_group_id in database.read_only_ad_group_ids : {
        name                    = "psql_flex_db_read_only_group_${database.db_name}_${database.db_env}_${ad_group_id}"
        ad_group_id             = ad_group_id
        psql_flex_database_name = database.db_name
        psql_flex_database_env  = database.db_env
        psql_flex_server_name   = database.psql_name
      }
    ]
  ])

  psqls_databases_extensions = flatten([
    for database in local.psqls_databases : [
      for extension in (local.is_prod_env) && !contains(database.extensions, "pgaudit") ? concat(database.extensions, ["pgaudit"]) : database.extensions  : {
        name                    = extension
        psql_flex_database_env  = database.db_env
        psql_flex_database_name = database.db_name
        psql_flex_server_name   = database.psql_name
        shared_library          = contains(["auto_explain","azure_storage","pg_cron","pg_failover_slots","pg_hint_plan","pg_partman_bgw","pg_prewarm","pg_squeeze","pg_stat_statements","pgaudit","pglogical","timescaledb","wal2json"], extension) ? true : false
      }
    ]
  ])

  psqls_databases = [
    for database in var.psqls_databases : (database.db_env == null) ? merge(database, { db_env : var.environment }) : database
  ]

  all_psql_tags = merge(local.all_tags, { "psqlcreatetimestamp" = timestamp() })
}

resource "azurerm_postgresql_flexible_server" "psql" {
  for_each   = { for psql in var.psqls : psql.name => psql }
  depends_on = [azurerm_private_dns_zone_virtual_network_link.psql_vnetlink_postgresqldb, azurerm_private_dns_zone_virtual_network_link.psql_vnetlink_infoblox_com1_usc, azurerm_private_dns_zone_virtual_network_link.psql_vnetlink_infoblox_com1_use2, azurerm_private_dns_zone_virtual_network_link.psql_vnetlink_infoblox_securehub_usc, azurerm_private_dns_zone_virtual_network_link.psql_vnetlink_infoblox_securehub_use2]

  name                   = "psql-flex-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.value.name}"
  resource_group_name    = !contains(var.resource_groups, "db") ? azurerm_resource_group.db_rg[0].name : azurerm_resource_group.ud_rgs["db"].name
  location               = var.location
  administrator_login    = "postgresauto"
  administrator_password = random_password.password_psql_flex[0].result

  authentication {
    password_auth_enabled         = true
    active_directory_auth_enabled = true
    tenant_id                     = data.azurerm_client_config.current.tenant_id
  }
  sku_name                          = local.dbaas_sizing_map[each.value.dbaas_standard_size].sku_name
  storage_mb                        = each.value.storage_mb == null ? local.dbaas_sizing_map[each.value.dbaas_standard_size].storage_mb : each.value.storage_mb
  version                           = each.value.version
  backup_retention_days             = local.is_prod_env ? 21 : 14
  delegated_subnet_id               = azurerm_subnet.subnets[each.value.delegated_subnet_name].id
  private_dns_zone_id               = azurerm_private_dns_zone.psql_dns[0].id
  create_mode                       = each.value.create_mode
  source_server_id                  = each.value.source_server_id
  point_in_time_restore_time_in_utc = each.value.point_in_time_restore_time_in_utc
  geo_redundant_backup_enabled      = (local.is_prod_env || each.value.grb_nonprod_requested) ? true : false
  auto_grow_enabled                 = each.value.auto_grow_enabled

  maintenance_window {
    day_of_week  = each.value.maintenance_window.maintenance_day
    start_hour   = each.value.maintenance_window.maintenance_hour
    start_minute = each.value.maintenance_window.maintenance_minute
  }

  dynamic "high_availability" {
    for_each = each.value.ha_enabled ? [1] : []
    content {
      mode = "ZoneRedundant"
    }
  }

  #use base key for cross region if no user input for geo backup key id
  dynamic "customer_managed_key" {
    for_each = (each.value.grb_nonprod_requested || local.is_prod_env) ? [1] : []
    content {
      key_vault_key_id                     = local.base_key_id
      primary_user_assigned_identity_id    = azurerm_user_assigned_identity.base_kv_uai[0].id
      geo_backup_key_vault_key_id          = each.value.geo_backup_key_vault_key_id == null? local.cross_region_base_key_id : each.value.geo_backup_key_vault_key_id
      geo_backup_user_assigned_identity_id = each.value.geo_backup_user_assigned_identity_id == null? local.cross_region_user_managed_id : each.value.geo_backup_user_assigned_identity_id
    }
  }

  dynamic "customer_managed_key" {
    for_each = (!each.value.grb_nonprod_requested && !local.is_prod_env) ? [1] : []
    content {
      key_vault_key_id                  = local.base_key_id
      primary_user_assigned_identity_id = azurerm_user_assigned_identity.base_kv_uai[0].id
    }
  }

  #add user identity for base key found for cross region if no user input provided
  dynamic "identity" {
    for_each = ((each.value.grb_nonprod_requested || local.is_prod_env) && each.value.geo_backup_user_assigned_identity_id == null)? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [azurerm_user_assigned_identity.base_kv_uai[0].id, local.cross_region_user_managed_id]
    }
  }

  #add user identity from user input if provided
  dynamic "identity" {
    for_each = ((each.value.grb_nonprod_requested || local.is_prod_env) && each.value.geo_backup_user_assigned_identity_id != null)? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [azurerm_user_assigned_identity.base_kv_uai[0].id, each.value.geo_backup_user_assigned_identity_id]
    }
  }

  dynamic "identity" {
    for_each = (!each.value.grb_nonprod_requested && !local.is_prod_env) ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [azurerm_user_assigned_identity.base_kv_uai[0].id]
    }
  }

  tags = local.all_psql_tags
  lifecycle {
    ignore_changes = [
      tags,
      zone,
      high_availability.0.standby_availability_zone
    ]
  }
}

locals {
  dns_zone_tags = {
    "requestId" : contains(keys(var.optional_tags), "requestId") ? var.optional_tags.requestId : null
    "deployedBy" : contains(keys(var.optional_tags), "deployedBy") ? var.optional_tags.deployedBy : null
  }
}

# Sets a PostgreSQL Configuration value on an Azure PostgreSQL Flexible Server 
resource "azurerm_postgresql_flexible_server_configuration" "psql_extensions" {

  for_each = { for ex in local.psqls_databases_extensions : "${ex.psql_flex_database_name}_${ex.name}" => ex}  
  depends_on = [azurerm_postgresql_flexible_server_database.flex_db]

  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.psql[each.value.psql_flex_server_name].id
  value     = lower(each.value.name)
}

resource "azurerm_postgresql_flexible_server_configuration" "psql_shared_library" {
 
  for_each   = { for extension in local.psqls_databases_extensions : "${extension.name}_${extension.psql_flex_database_name}_${extension.psql_flex_database_env}" => extension if local.psqls_databases_extensions != [] && extension.shared_library} 
  depends_on = [azurerm_postgresql_flexible_server_configuration.psql_extensions]
  name       = "shared_preload_libraries"
  server_id  = azurerm_postgresql_flexible_server.psql[each.value.psql_flex_server_name].id
  value      = lower(each.value.name)
}

resource "azurerm_private_dns_zone" "psql_dns" {
  count               = length(var.psqls) > 0 ? 1 : 0
  name                = "${var.application_id}.${local.subscription_name_suffix}.${local.short_location_name}.cvs.${var.environment}.p.postgres.database.azure.com"
  resource_group_name = !contains(var.resource_groups, "db") ? azurerm_resource_group.db_rg[0].name : azurerm_resource_group.ud_rgs["db"].name

  tags = local.dns_zone_tags
  lifecycle {
    ignore_changes = [
      tags,
      name
    ]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "psql_vnetlink_postgresqldb" {
  count      = length(azurerm_private_dns_zone.psql_dns) > 0 ? 1 : 0
  depends_on = [azurerm_private_dns_zone.psql_dns]

  name                  = "postgresqldb"
  private_dns_zone_name = azurerm_private_dns_zone.psql_dns[0].name
  virtual_network_id    = local.vnet_id
  resource_group_name   = !contains(var.resource_groups, "db") ? azurerm_resource_group.db_rg[0].name : azurerm_resource_group.ud_rgs["db"].name

  tags = local.dns_zone_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "psql_vnetlink_infoblox_com1_usc" {
  count      = length(azurerm_private_dns_zone.psql_dns) > 0 ? 1 : 0
  depends_on = [azurerm_private_dns_zone.psql_dns]

  name                  = "infoblox-cvs-usc-com1"
  private_dns_zone_name = azurerm_private_dns_zone.psql_dns[0].name
  resource_group_name   = !contains(var.resource_groups, "db") ? azurerm_resource_group.db_rg[0].name : azurerm_resource_group.ud_rgs["db"].name
  virtual_network_id    = "/subscriptions/7f81ff32-74f5-45e3-bc03-a8141f72754d/resourceGroups/RG-CVS-USC-COM-1/providers/Microsoft.Network/virtualNetworks/VN-CVS-USC-COM-1"

  tags = local.dns_zone_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "psql_vnetlink_infoblox_com1_use2" {
  count      = length(azurerm_private_dns_zone.psql_dns) > 0 ? 1 : 0
  depends_on = [azurerm_private_dns_zone.psql_dns]

  name                  = "infoblox-cvs-use2-com1"
  private_dns_zone_name = azurerm_private_dns_zone.psql_dns[0].name
  resource_group_name   = !contains(var.resource_groups, "db") ? azurerm_resource_group.db_rg[0].name : azurerm_resource_group.ud_rgs["db"].name
  virtual_network_id    = "/subscriptions/7f81ff32-74f5-45e3-bc03-a8141f72754d/resourceGroups/RG-CVS-USE2-COM-1/providers/Microsoft.Network/virtualNetworks/VN-CVS-USE2-COM-1"

  tags = local.dns_zone_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "psql_vnetlink_infoblox_securehub_usc" {
  count      = length(azurerm_private_dns_zone.psql_dns) > 0 ? 1 : 0
  depends_on = [azurerm_private_dns_zone.psql_dns]

  name                  = "infoblox-cvs-usc-securehub"
  private_dns_zone_name = azurerm_private_dns_zone.psql_dns[0].name
  resource_group_name   = !contains(var.resource_groups, "db") ? azurerm_resource_group.db_rg[0].name : azurerm_resource_group.ud_rgs["db"].name
  virtual_network_id    = "/subscriptions/29ea5d6f-8539-4a95-8198-ca801994cbdb/resourceGroups/rg-cvsntwkhub000/providers/Microsoft.Network/virtualNetworks/vnet-cvshub001"

  tags = local.dns_zone_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "psql_vnetlink_infoblox_securehub_use2" {
  count      = length(azurerm_private_dns_zone.psql_dns) > 0 ? 1 : 0
  depends_on = [azurerm_private_dns_zone.psql_dns]

  name                  = "infoblox-cvs-use2-securehub"
  private_dns_zone_name = azurerm_private_dns_zone.psql_dns[0].name
  resource_group_name   = !contains(var.resource_groups, "db") ? azurerm_resource_group.db_rg[0].name : azurerm_resource_group.ud_rgs["db"].name
  virtual_network_id    = "/subscriptions/59b2cd00-9406-4a41-a772-e073dbe19796/resourceGroups/rg-cvsntwkhub000/providers/Microsoft.Network/virtualNetworks/vnet-cvshub000"

  tags = local.dns_zone_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_postgresql_flexible_server_active_directory_administrator" "psql_aad_admin_automation_spn" {
  for_each = { for psql in var.psqls : psql.name => psql if(psql.create_mode != "PointInTimeRestore") }

  server_name         = azurerm_postgresql_flexible_server.psql[each.value.name].name
  resource_group_name = azurerm_postgresql_flexible_server.psql[each.value.name].resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = local.automation_spn.object_id
  principal_name      = local.automation_spn.display_name
  principal_type      = "ServicePrincipal"
}

resource "azurerm_postgresql_flexible_server_active_directory_administrator" "psql_aad_admin_dba_ops" {
  for_each = { for psql in var.psqls : psql.name => psql if(psql.create_mode != "PointInTimeRestore") }

  server_name         = azurerm_postgresql_flexible_server.psql[each.value.name].name
  resource_group_name = azurerm_postgresql_flexible_server.psql[each.value.name].resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = each.value.test_mode ? "9749dd0e-113e-4f50-a8b3-288e223d604b" : "fd5c85a2-aa27-41c4-8b35-b0c199cd50f8"
  principal_name      = each.value.test_mode ? "CLGRP-AAD-PE-DBAAS-AZURE" : "CLGRP-AAD-DBA-Operations"
  principal_type      = "Group"
}

resource "azurerm_postgresql_flexible_server_database" "flex_db" {
  for_each  = { for database in local.psqls_databases : "${database.db_name}_${database.db_env}" => database }
  name      = "${each.value.db_name}_${each.value.db_env}_pgs_db"
  server_id = azurerm_postgresql_flexible_server.psql[each.value.psql_name].id
  charset   = each.value.charset
  collation = each.value.collation
}

resource "null_resource" "psql_postgres_user" {
  for_each   = { for psql in var.psqls : psql.name => psql if(psql.create_mode != "PointInTimeRestore") }
  depends_on = [azurerm_postgresql_flexible_server.psql]

  triggers = {
    subscription_id     = split("/", data.azurerm_subscription.current.id)[2]
    psql_flex           = azurerm_postgresql_flexible_server.psql[each.value.name].name
    psqlcreatetimestamp = azurerm_postgresql_flexible_server.psql[each.value.name].tags.psqlcreatetimestamp
    working_dir         = "${path.module}/scripts"
  }

  provisioner "local-exec" {
    when        = create
    working_dir = "${path.module}/scripts"
    command     = "chmod +x psql_create_postgres_user.sh; ./psql_create_postgres_user.sh \"$PG_ADMIN_PASSWORD\" \"$PSQL_FLEX_SERVER_NAME\" \"$POSTGRES_EC_PWD\""

    environment = {
      PG_ADMIN_PASSWORD     = urlencode(azurerm_postgresql_flexible_server.psql[each.value.name].administrator_password)
      PSQL_FLEX_SERVER_NAME = self.triggers.psql_flex
    }
  }
}

resource "null_resource" "psql_schema" {
  for_each   = { for database in local.psqls_databases : "${database.db_name}_${database.db_env}_schema" => database }
  depends_on = [azurerm_postgresql_flexible_server_database.flex_db]

  triggers = {
    subscription_id     = split("/", data.azurerm_subscription.current.id)[2]
    psql_flex_rg        = azurerm_postgresql_flexible_server.psql[each.value.psql_name].resource_group_name
    psql_flex           = azurerm_postgresql_flexible_server.psql[each.value.psql_name].name
    psql_db_name        = azurerm_postgresql_flexible_server_database.flex_db["${each.value.db_name}_${each.value.db_env}"].name
    psqlcreatetimestamp = azurerm_postgresql_flexible_server.psql[each.value.psql_name].tags.psqlcreatetimestamp
  }

  provisioner "local-exec" {
    when        = create
    working_dir = "${path.module}/scripts"
    command     = "chmod +x psql_create_schema_and_roles.sh; ./psql_create_schema_and_roles.sh \"$PG_ADMIN_PASSWORD\" \"$PSQL_FLEX_SERVER_NAME\" \"$PSQL_DATABASE_NAME\""

    environment = {
      PG_ADMIN_PASSWORD     = urlencode(azurerm_postgresql_flexible_server.psql[each.value.psql_name].administrator_password)
      PSQL_FLEX_SERVER_NAME = self.triggers.psql_flex
      PSQL_DATABASE_NAME    = self.triggers.psql_db_name
    }
  }

  # Don't need a destroy block because schema gets deleted along with the database
}

resource "null_resource" "psql_extension" {
  for_each   = { for extension in local.psqls_databases_extensions : "extension_${extension.name}_${extension.psql_flex_database_name}_${extension.psql_flex_database_env}" => extension } 
  depends_on = [azurerm_postgresql_flexible_server_database.flex_db, azurerm_postgresql_flexible_server_configuration.psql_extensions, azurerm_postgresql_flexible_server_configuration.psql_shared_library]

  triggers = {
    subscription_id     = split("/", data.azurerm_subscription.current.id)[2]
    psql_flex_rg        = azurerm_postgresql_flexible_server.psql[each.value.psql_flex_server_name].resource_group_name
    psql_flex           = azurerm_postgresql_flexible_server.psql[each.value.psql_flex_server_name].name
    psqlcreatetimestamp = azurerm_postgresql_flexible_server.psql[each.value.psql_flex_server_name].tags.psqlcreatetimestamp
    psql_db_name        = azurerm_postgresql_flexible_server_database.flex_db["${each.value.psql_flex_database_name}_${each.value.psql_flex_database_env}"].name
    psql_db_extension   = each.value.name
  }

  provisioner "local-exec" {
    when        = create
    working_dir = "${path.module}/scripts"
    command     = "chmod +x psql_create_extension.sh; ./psql_create_extension.sh \"$PG_ADMIN_PASSWORD\" \"$PSQL_FLEX_SERVER_NAME\" \"$PSQL_DATABASE_NAME\" \"$PSQL_DATABASE_EXTENSION\""
  
    environment = {
      PG_ADMIN_PASSWORD       = urlencode(azurerm_postgresql_flexible_server.psql[each.value.psql_flex_server_name].administrator_password)
      PSQL_FLEX_SERVER_NAME   = self.triggers.psql_flex
      PSQL_DATABASE_NAME      = self.triggers.psql_db_name
      PSQL_DATABASE_EXTENSION = self.triggers.psql_db_extension
    }
  }
}

resource "null_resource" "psql_ddl_users" {
  for_each   = { for ddl_user in local.psql_flex_db_ddl_ud_mi_users : "ddl_${ddl_user.ud_mi_name}_${ddl_user.psql_flex_database_name}_${ddl_user.psql_flex_database_env}" => ddl_user }
  depends_on = [azurerm_postgresql_flexible_server_database.flex_db, azurerm_user_assigned_identity.ud_managed_identity, null_resource.psql_schema, azurerm_postgresql_flexible_server_active_directory_administrator.psql_aad_admin_automation_spn]

  triggers = {
    subscription_id     = split("/", data.azurerm_subscription.current.id)[2]
    psql_flex_rg        = azurerm_postgresql_flexible_server.psql[each.value.psql_flex_server_name].resource_group_name
    pg_aad_admin        = local.automation_spn.display_name
    psql_flex           = azurerm_postgresql_flexible_server.psql[each.value.psql_flex_server_name].name
    psql_db_name        = azurerm_postgresql_flexible_server_database.flex_db["${each.value.psql_flex_database_name}_${each.value.psql_flex_database_env}"].name
    ud_mi_name          = each.value.ud_mi_name
    ud_mi_oid           = azurerm_user_assigned_identity.ud_managed_identity[each.value.ud_mi_name].principal_id
    working_dir         = "${path.module}/scripts"
    destroy_command     = "chmod +x psql_delete_user.sh; ./psql_delete_user.sh \"$PG_AAD_ADMIN\" \"$PSQL_FLEX_SERVER_NAME\" \"$PSQL_DATABASE_NAME\" \"$PG_MI_USERNAME\""
    psqlcreatetimestamp = azurerm_postgresql_flexible_server.psql[each.value.psql_flex_server_name].tags.psqlcreatetimestamp
  }

  provisioner "local-exec" {
    when        = create
    working_dir = "${path.module}/scripts"
    command     = "chmod +x azlogin_oidc.sh; ./azlogin_oidc.sh; chmod +x psql_create_ddl_user.sh; ./psql_create_ddl_user.sh \"$PG_AAD_ADMIN\" \"$PSQL_FLEX_SERVER_NAME\" \"$PSQL_DATABASE_NAME\" \"$PG_MI_USERNAME\" \"$MANAGED_IDENTITY_OBJECT_ID\""

    environment = {
      PG_AAD_ADMIN               = self.triggers.pg_aad_admin
      PSQL_FLEX_SERVER_NAME      = self.triggers.psql_flex
      PSQL_DATABASE_NAME         = self.triggers.psql_db_name
      PG_MI_USERNAME             = "${self.triggers.ud_mi_name}_${self.triggers.psql_db_name}"
      MANAGED_IDENTITY_OBJECT_ID = self.triggers.ud_mi_oid
    }
  }

  provisioner "local-exec" {
    when        = destroy
    working_dir = self.triggers.working_dir
    command     = self.triggers.destroy_command

    environment = {
      PG_AAD_ADMIN          = self.triggers.pg_aad_admin
      PSQL_FLEX_SERVER_NAME = self.triggers.psql_flex
      PSQL_DATABASE_NAME    = self.triggers.psql_db_name
      PG_MI_USERNAME        = "${self.triggers.ud_mi_name}_${self.triggers.psql_db_name}"
    }
  }
}

resource "null_resource" "psql_dml_users" {
  for_each   = { for dml_user in local.psql_flex_db_dml_ud_mi_users : "dml_${dml_user.ud_mi_name}_${dml_user.psql_flex_database_name}_${dml_user.psql_flex_database_env}" => dml_user }
  depends_on = [azurerm_postgresql_flexible_server_database.flex_db, azurerm_user_assigned_identity.ud_managed_identity, null_resource.psql_schema, azurerm_postgresql_flexible_server_active_directory_administrator.psql_aad_admin_automation_spn]

  triggers = {
    subscription_id     = split("/", data.azurerm_subscription.current.id)[2]
    psql_flex_rg        = azurerm_postgresql_flexible_server.psql[each.value.psql_flex_server_name].resource_group_name
    pg_aad_admin        = local.automation_spn.display_name
    psql_flex           = azurerm_postgresql_flexible_server.psql[each.value.psql_flex_server_name].name
    psql_db_name        = azurerm_postgresql_flexible_server_database.flex_db["${each.value.psql_flex_database_name}_${each.value.psql_flex_database_env}"].name
    ud_mi_name          = each.value.ud_mi_name
    ud_mi_oid           = azurerm_user_assigned_identity.ud_managed_identity[each.value.ud_mi_name].principal_id
    working_dir         = "${path.module}/scripts"
    destroy_command     = "chmod +x psql_delete_user.sh; ./psql_delete_user.sh \"$PG_AAD_ADMIN\" \"$PSQL_FLEX_SERVER_NAME\" \"$PSQL_DATABASE_NAME\" \"$PG_MI_USERNAME\""
    psqlcreatetimestamp = azurerm_postgresql_flexible_server.psql[each.value.psql_flex_server_name].tags.psqlcreatetimestamp
  }

  provisioner "local-exec" {
    when        = create
    working_dir = "${path.module}/scripts"
    command     = "chmod +x azlogin_oidc.sh; ./azlogin_oidc.sh; chmod +x psql_create_dml_user.sh; ./psql_create_dml_user.sh \"$PG_AAD_ADMIN\" \"$PSQL_FLEX_SERVER_NAME\" \"$PSQL_DATABASE_NAME\" \"$PG_MI_USERNAME\" \"$MANAGED_IDENTITY_OBJECT_ID\""

    environment = {
      PG_AAD_ADMIN               = self.triggers.pg_aad_admin
      PSQL_FLEX_SERVER_NAME      = self.triggers.psql_flex
      PSQL_DATABASE_NAME         = self.triggers.psql_db_name
      PG_MI_USERNAME             = "${self.triggers.ud_mi_name}_${self.triggers.psql_db_name}"
      MANAGED_IDENTITY_OBJECT_ID = self.triggers.ud_mi_oid
    }
  }

  provisioner "local-exec" {
    when        = destroy
    working_dir = self.triggers.working_dir
    command     = self.triggers.destroy_command

    environment = {
      PG_AAD_ADMIN          = self.triggers.pg_aad_admin
      PSQL_FLEX_SERVER_NAME = self.triggers.psql_flex
      PSQL_DATABASE_NAME    = self.triggers.psql_db_name
      PG_MI_USERNAME        = "${self.triggers.ud_mi_name}_${self.triggers.psql_db_name}"
    }
  }
}

resource "null_resource" "psql_read_only_groups" {
  for_each   = { for read_only_group in local.psql_flex_db_read_only_groups : "ro_${read_only_group.ad_group_id}_${read_only_group.psql_flex_database_name}_${read_only_group.psql_flex_database_env}" => read_only_group }
  depends_on = [azurerm_postgresql_flexible_server_database.flex_db, null_resource.psql_schema, azurerm_postgresql_flexible_server_active_directory_administrator.psql_aad_admin_automation_spn]

  triggers = {
    subscription_id     = split("/", data.azurerm_subscription.current.id)[2]
    psql_flex_rg        = azurerm_postgresql_flexible_server.psql[each.value.psql_flex_server_name].resource_group_name
    pg_aad_admin        = local.automation_spn.display_name
    psql_flex           = azurerm_postgresql_flexible_server.psql[each.value.psql_flex_server_name].name
    psql_db_name        = azurerm_postgresql_flexible_server_database.flex_db["${each.value.psql_flex_database_name}_${each.value.psql_flex_database_env}"].name
    ad_group_id         = each.value.ad_group_id
    working_dir         = "${path.module}/scripts"
    destroy_command     = "chmod +x psql_delete_user.sh; ./psql_delete_user.sh \"$PG_AAD_ADMIN\" \"$PSQL_FLEX_SERVER_NAME\" \"$PSQL_DATABASE_NAME\" \"aad_group_ro_${each.value.ad_group_id}\""
    psqlcreatetimestamp = azurerm_postgresql_flexible_server.psql[each.value.psql_flex_server_name].tags.psqlcreatetimestamp
  }

  provisioner "local-exec" {
    when        = create
    working_dir = "${path.module}/scripts"
    command     = "chmod +x psql_create_select_user.sh; ./psql_create_select_user.sh \"$PG_AAD_ADMIN\" \"$PSQL_FLEX_SERVER_NAME\" \"$PSQL_DATABASE_NAME\" \"$AD_GROUP_ID\""

    environment = {
      PG_AAD_ADMIN          = self.triggers.pg_aad_admin
      PSQL_FLEX_SERVER_NAME = self.triggers.psql_flex
      PSQL_DATABASE_NAME    = self.triggers.psql_db_name
      AD_GROUP_ID           = self.triggers.ad_group_id
    }
  }

  provisioner "local-exec" {
    when        = destroy
    working_dir = self.triggers.working_dir
    command     = self.triggers.destroy_command

    environment = {
      PG_AAD_ADMIN          = self.triggers.pg_aad_admin
      PSQL_FLEX_SERVER_NAME = self.triggers.psql_flex
      PSQL_DATABASE_NAME    = self.triggers.psql_db_name
      AD_GROUP_ID           = self.triggers.ad_group_id
    }
  }
}
