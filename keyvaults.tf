data "azurerm_client_config" "current" {}

locals {
  environment_code_map = {
    "dev"     = "01"
    "preprod" = "02"
    "nonprod" = "03"
    "qa"      = "04"
    "pt"      = "05"
    "uat"     = "06"
    "prod"    = "07"
    "dr"      = "08"
  }

  short_location_name_code_map = {
    "use2" = "01"
    "usc"  = "02"
    "usw3" = "03"  
    "use"  = "04"
    }

  eventhub_info = {
    "centralus_prod" = {
      eventhub_authorization_rule_id = "/subscriptions/7f81ff32-74f5-45e3-bc03-a8141f72754d/resourceGroups/RG-CVS-SharedServices-2/providers/Microsoft.EventHub/namespaces/rac2ehnpp2v/authorizationRules/RootManageSharedAccessKey"
      eventhub_name                  = "cvs-splunk-azure-logs"
    }
    "eastus2_prod" = {
      eventhub_authorization_rule_id = "/subscriptions/7f81ff32-74f5-45e3-bc03-a8141f72754d/resourceGroups/RG-CVS-SharedServices-1/providers/Microsoft.EventHub/namespaces/rac2ehnpp1v/authorizationRules/RootManageSharedAccessKey"
      eventhub_name                  = "cvs-splunk-azure-logs"
    }
    #ALL VALUES BELOW NEED UPDATE; PLACEHOLDERS
    "eastus_prod" = {
      eventhub_authorization_rule_id = "/subscriptions/7f81ff32-74f5-45e3-bc03-a8141f72754d/resourceGroups/RG-CVS-SharedServices-2/providers/Microsoft.EventHub/namespaces/rac2ehnpp2v/authorizationRules/RootManageSharedAccessKey"
      eventhub_name                  = "cvs-splunk-azure-logs"
    }
    "westus3_prod" = {
      eventhub_authorization_rule_id = "/subscriptions/7f81ff32-74f5-45e3-bc03-a8141f72754d/resourceGroups/RG-CVS-SharedServices-1/providers/Microsoft.EventHub/namespaces/rac2ehnpp1v/authorizationRules/RootManageSharedAccessKey"
      eventhub_name                  = "cvs-splunk-azure-logs"
    }
    "centralus_nonprod" = {
      eventhub_authorization_rule_id = "/subscriptions/7f81ff32-74f5-45e3-bc03-a8141f72754d/resourceGroups/RG-CVS-SharedServices-2/providers/Microsoft.EventHub/namespaces/rac2ehnpp2v/authorizationRules/RootManageSharedAccessKey"
      eventhub_name                  = "cvs-splunk-azure-logs"
    }
    "eastus2_nonprod" = {
      eventhub_authorization_rule_id = "/subscriptions/7f81ff32-74f5-45e3-bc03-a8141f72754d/resourceGroups/RG-CVS-SharedServices-1/providers/Microsoft.EventHub/namespaces/rac2ehnpp1v/authorizationRules/RootManageSharedAccessKey"
      eventhub_name                  = "cvs-splunk-azure-logs"
    }
    "eastus_nonprod" = {
      eventhub_authorization_rule_id = "/subscriptions/7f81ff32-74f5-45e3-bc03-a8141f72754d/resourceGroups/RG-CVS-SharedServices-2/providers/Microsoft.EventHub/namespaces/rac2ehnpp2v/authorizationRules/RootManageSharedAccessKey"
      eventhub_name                  = "cvs-splunk-azure-logs"
    }
    "westus3_nonprod" = {
      eventhub_authorization_rule_id = "/subscriptions/7f81ff32-74f5-45e3-bc03-a8141f72754d/resourceGroups/RG-CVS-SharedServices-1/providers/Microsoft.EventHub/namespaces/rac2ehnpp1v/authorizationRules/RootManageSharedAccessKey"
      eventhub_name                  = "cvs-splunk-azure-logs"
    }
    #ALL VALUES ABOVE NEED UPDATE; PLACEHOLDERS
  }

  env_region_code = "${lookup(local.environment_code_map, var.environment, "99")}${lookup(local.short_location_name_code_map, local.short_location_name, "99")}"

  env_region = var.is_former_kv_naming_convention ? "${var.environment}${local.short_location_name}" : local.env_region_code

  ud_key_vault_secrets_user_permissions = flatten([
    for kv in var.key_vaults : [
      for identity in kv.secrets_user : {
        name         = "secrets_user_${kv.name}_${identity}"
        principal_id = identity
        scope        = azurerm_key_vault.ud_key_vaults["${kv.name}"].id
      }
    ]
  ])

  ud_key_vault_ud_mi_secrets_user_permissions = flatten([
    for kv in var.key_vaults : [
      for mi_name in kv.ud_mi_secrets_user : {
        name       = "ud_mi_secrets_user_${kv.name}_${mi_name}"
        ud_mi_name = mi_name
        scope      = azurerm_key_vault.ud_key_vaults["${kv.name}"].id
      }
    ]
  ])

  ud_key_vault_crypto_user_permissions = flatten([
    for kv in var.key_vaults : [
      for identity in kv.crypto_user : {
        name         = "crypto_user_${kv.name}_${identity}"
        principal_id = identity
        scope        = azurerm_key_vault.ud_key_vaults["${kv.name}"].id
      }
    ]
  ])

  ud_key_vault_ud_mi_crypto_user_permissions = flatten([
    for kv in var.key_vaults : [
      for mi_name in kv.ud_mi_crypto_user : {
        name         = "ud_mi_crypto_user_${kv.name}_${mi_name}"
        principal_id = azurerm_user_assigned_identity.ud_managed_identity[mi_name].principal_id
        scope        = azurerm_key_vault.ud_key_vaults["${kv.name}"].id
      }
    ]
  ])

  ud_key_vault_admin_permissions = flatten([
    for kv in var.key_vaults : [
      for identity in kv.key_vault_admin : {
        name         = "key_vault_admin_${kv.name}_${identity}"
        principal_id = identity
        scope        = azurerm_key_vault.ud_key_vaults["${kv.name}"].id
      }
    ]
  ])

  ud_key_vault_ud_mi_key_vault_admin_permissions = flatten([
    for kv in var.key_vaults : [
      for mi_name in kv.ud_mi_key_vault_admin : {
        name         = "ud_mi_key_vault_admin_${kv.name}_${mi_name}"
        principal_id = azurerm_user_assigned_identity.ud_managed_identity[mi_name].principal_id
        scope        = azurerm_key_vault.ud_key_vaults["${kv.name}"].id
      }
    ]
  ])

  	
  ud_key_vault_keys = flatten([
    for kv in var.key_vaults : [
      for key in kv.keys : {
        key_name            = key.name
        key_vault_name      = kv.name
        enable_rotation = key.enable_rotation
      }
    ]
  ])
}

resource "random_string" "kvname" {
  length  = 6
  special = false
  upper   = false
}

locals {
  random_kv_names = tobool(var.random_kv_names || var.is_host)
}

resource "azurerm_key_vault" "ud_key_vaults" {
  depends_on = [local.peering_resources]

  for_each = { for kv in var.key_vaults : kv.name => kv }

  name                          = var.random_kv_names ? "kv-${var.application_id}${each.key}${random_string.kvname.result}" : "kv-${var.line_of_business}${var.application_id}${local.env_region}${each.key}"
  location                      = var.location
  resource_group_name           = each.value.resource_group_name != null ? each.value.resource_group_name : each.value.resource_group != null ? azurerm_resource_group.ud_rgs[lower(each.value.resource_group)].name : azurerm_resource_group.secr_rg[0].name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days    = each.value.soft_delete_retention_days
  purge_protection_enabled      = each.value.purge_protection_enabled
  sku_name                      = var.legacy_standard_kv ? each.value.sku_name : "premium"
  enable_rbac_authorization     = true
  public_network_access_enabled = false
  network_acls {
    default_action = var.public_keyvaults ? "Allow" : "Deny"
    bypass         = "AzureServices"
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags,
      enabled_for_template_deployment,
      name
    ]
  }
}
resource "azurerm_key_vault_key" "ud_kv_key" {
  depends_on = [azurerm_private_endpoint.ud_key_vaults_pes, local.keys_depend_on]
  for_each = { for key in local.ud_key_vault_keys : key.key_name => key }
  name            = "key-${each.key}-${random_string.kvname.result}"
  key_vault_id    = azurerm_key_vault.ud_key_vaults[each.value.key_vault_name].id
  key_type        = "RSA-HSM"
  key_size        = 2048
  # expiration_date = timeadd(timestamp(), "87600h")
  dynamic "rotation_policy" {
    for_each = each.value.enable_rotation ? [1] : []
    content {
      automatic {
        time_after_creation = "P1Y"
      }
    }
  }
  
  key_opts = [
    "decrypt",
    "encrypt",
    "unwrapKey",
    "wrapKey",
  ]
  lifecycle {
    ignore_changes = [
      expiration_date
    ]
  }
}

resource "azurerm_private_endpoint" "ud_key_vaults_pes" {
  for_each            = { for kv in var.key_vaults : kv.name => kv if kv.subnet_name != null || kv.external_subnet_id != null }
  name                = "pep-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-kv-${each.value.name}"
  location            = var.location
  resource_group_name = each.value.resource_group_name != null ? each.value.resource_group_name : each.value.resource_group != null ? azurerm_resource_group.ud_rgs[lower(each.value.resource_group)].name : azurerm_resource_group.secr_rg[0].name
  subnet_id           = each.value.external_subnet_id != null ? each.value.external_subnet_id : azurerm_subnet.subnets[each.value.subnet_name].id

  private_service_connection {
    name                           = "${each.value.name}-privateserviceconnection"
    private_connection_resource_id = azurerm_key_vault.ud_key_vaults["${each.value.name}"].id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }

  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.vaultcore.azure.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }
}

# resource "null_resource" "delete_ud_kv_pep_dns_when_destroyed" {
#   for_each = { for pep in azurerm_private_endpoint.ud_key_vaults_pes : pep.name => pep }
#   triggers = {
#     working_dir    = local.script_dir
#     delete_command = local.dns_command_delete
#     hostname       = "${split(".", each.value.custom_dns_configs[0].fqdn)[0]}.privatelink.vaultcore.azure.net"
#     ip_address     = each.value.private_service_connection[0].private_ip_address
#   }

#   provisioner "local-exec" {
#     when        = destroy
#     working_dir = self.triggers.working_dir
#     command     = self.triggers.delete_command
#     environment = {
#       LABEL = self.triggers.hostname
#       IP       = self.triggers.ip_address
#     }
#   }
# }

data "azurerm_resources" "host_base_key_vault" {
  count               = local.is_client ? 1 : 0
  resource_group_name = "rg-${local.host_name_prefix}-secr${local.host_rg_suffix}"
  type                = "Microsoft.KeyVault/vaults"

  required_tags = {
    host = "true"
    custom = null
  }
}

data "azurerm_key_vault" "host_base_kv" {
  count               = local.is_client ? 1 : 0
  name                = data.azurerm_resources.host_base_key_vault[0].resources[0].name
  resource_group_name = data.azurerm_resources.host_base_key_vault[0].resources[0].resource_group_name

}

#get custom key vault for host in case custom key is needed and shared vnet
data "azurerm_resources" "host_custom_key_vault" {
  count               = (local.db_use_custom_key_vault && local.need_custom_key_vault && local.is_client) ? 1 : 0
  resource_group_name = "rg-${local.host_name_prefix}-secr${local.host_rg_suffix}"
  type                = "Microsoft.KeyVault/vaults"

  required_tags = {
    host = "true"
    custom = "true"
  }
}

#get cross region key vault in case of grb is needed(db type supports grb and env is pt or prod)
data "azurerm_resources" "cross_region_base_key_vault" {
  count               = ((local.is_client || var.is_spoke) && length(local.db_grb_list) > 0) ? 1 : 0
  resource_group_name = local.cross_region_base_kv_rg_id
  type                = "Microsoft.KeyVault/vaults"

  required_tags = {
    custom = null
    base = "true"
  }
}

data "azurerm_key_vault" "cross_region_base_kv" {
  count               = length(data.azurerm_resources.cross_region_base_key_vault)>0 ? 1 : 0
  name                = data.azurerm_resources.cross_region_base_key_vault[0].resources[0].name
  resource_group_name = data.azurerm_resources.cross_region_base_key_vault[0].resources[0].resource_group_name
}

#get cross region key vault user managed identity in case of grb is needed(db type supports grb and env is pt or prod)
data "azurerm_resources" "cross_region_base_kv_uai" {
  count               = ((local.is_client || var.is_spoke) && length(local.db_grb_list) > 0) ? 1 : 0
  resource_group_name = local.cross_region_base_kv_rg_id
  type                = "Microsoft.ManagedIdentity/userAssignedIdentities"
}

#get cross region key vault key
data "azurerm_key_vault_key" "cross_region_base_key" {
  count        = local.cross_region_base_key_vault_id != null ? 1 : 0
  key_vault_id = local.cross_region_base_key_vault_id
  name         = local.cross_region_key_name
}

#get cross region custom key vaults in case of custom key and grb are needed(db type supports grb and env is pt or prod)
data "azurerm_resources" "cross_region_base_custom_key_vault" {
  count      = local.use_custom_cross_region_key_vault ? 1 : 0

  resource_group_name = local.cross_region_base_kv_rg_id
  type                = "Microsoft.KeyVault/vaults"

  required_tags = {
    soft-delete = "90"
    custom = "true"
  }
}

#get cross region custom key vaults keys
data "azurerm_key_vault_key" "cross_region_cutom_base_key" {
  count      = local.use_custom_cross_region_key_vault ? 1 : 0

  key_vault_id = data.azurerm_resources.cross_region_base_custom_key_vault[0].resources[0].id
  name         = "key-custom-${local.cross_region_custom_kv_suffix}"
}

locals {
  host_kv_suffix = local.is_client ? substr(data.azurerm_resources.host_base_key_vault[0].resources[0].name, -6, -1) : null
  host_kv_prefix = local.is_client ? trimsuffix(split("-", data.azurerm_resources.host_base_key_vault[0].resources[0].name)[1], local.host_kv_suffix) : null
  host_key_name  = local.is_client ? lower("key-${local.host_kv_prefix}-${var.location}-${var.required_tags.environmenttype}${local.host_kv_suffix}") : null
  
  #get cross region key name using cross region key vault name
  #check if key vault is random from key vault name
  is_cross_region_key_vault_random = local.cross_region_base_key_vault_name != null ? !strcontains(local.cross_region_base_key_vault_name, var.line_of_business) : false
  #get random string from key vault name
  cross_region_kv_suffix           = local.is_cross_region_key_vault_random ? substr(local.cross_region_base_key_vault_name, -6, -1) : ""
  cross_region_kv_prefix           = local.is_cross_region_key_vault_random ? trimsuffix(split("-", local.cross_region_base_key_vault_name)[1], local.cross_region_kv_suffix) : var.application_id
  cross_region_environment         = local.is_client ? "${var.required_tags.environmenttype}" : "${var.environment}"
  cross_region_key_name            = local.cross_region_base_key_vault_name != null ? lower("key-${local.cross_region_kv_prefix}-${local.cross_region_location}-${local.cross_region_environment}${local.cross_region_kv_suffix}") : null

  #get random string from cross region custom key vault name
  cross_region_custom_kv_suffix    = length(data.azurerm_resources.cross_region_base_custom_key_vault) >0 ? substr(data.azurerm_resources.cross_region_base_custom_key_vault[0].resources[0].name, -6, -1) : ""

  #validate if custom key vault is missing in case it is needed and shared vnet
  validate_custom_key_vault = (local.db_use_custom_key_vault && local.need_custom_key_vault && local.is_client)? (length(data.azurerm_resources.host_custom_key_vault[0].resources) == 0? tobool("${local.ec_error_aheader} ${local.ec_error_custom_key_vault} ${local.ec_error_zfooter}") : true) : true
  #validate that single tenant spoke file has custom key if needed
  validate_custom_cross_region_key_vault_single = (local.use_custom_cross_region_key_vault && !local.is_client)? (length(data.azurerm_resources.cross_region_base_custom_key_vault[0].resources) == 0? tobool("${local.ec_error_aheader} ${local.ec_error_cross_region_custom_key_vault_single} ${local.ec_error_zfooter}") : true) : true
  #validate that host file has custom key if needed and shared vnet
  validate_custom_cross_region_key_vault_shared = (local.use_custom_cross_region_key_vault && local.is_client)? (length(data.azurerm_resources.cross_region_base_custom_key_vault[0].resources) == 0? tobool("${local.ec_error_aheader} ${local.ec_error_cross_region_custom_key_vault_shared} ${local.ec_error_zfooter}") : true) : true
  #validate base key vault has base tag
  validate_cross_region_key_vault = ((local.is_client || var.is_spoke) && length(local.db_grb_list) > 0)? (length(data.azurerm_resources.cross_region_base_key_vault[0].resources) == 0? tobool("${local.ec_error_aheader} ${local.ec_error_cross_region_key_vault} ${local.ec_error_zfooter}") : true) : true
}

# data "azurerm_key_vault_key" "host_base_key" {
#   count        = local.is_client ? 1 : 0
#   name         = local.host_key_name
#   key_vault_id = local.base_kv_id
# }
#

#custom key vault to be created in case host base key vault is not 90 soft delete retention days
#or single tenant spoke base key is not 90 soft delete retention days and has servers requiring that
resource "azurerm_key_vault" "base_custom_kv" {
  depends_on = [local.peering_resources, azurerm_key_vault.base_kv]
  count      = local.use_custom_key_vault && local.build_base_resources ? 1 : 0

  name                          = "kv-${var.application_id}custom${random_string.kvname.result}"
  location                      = azurerm_resource_group.secr_rg[0].location
  resource_group_name           = azurerm_resource_group.secr_rg[0].name
  enabled_for_disk_encryption   = true
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days    = 90
  purge_protection_enabled      = true
  enable_rbac_authorization     = true
  public_network_access_enabled = var.public_keyvaults
  sku_name                      = "premium"
  network_acls {
    default_action = var.public_keyvaults ? "Allow" : "Deny"
    bypass         = "AzureServices"
  }

  tags = merge(local.all_tags, { soft-delete : 90, custom : true })

  lifecycle {
    ignore_changes = [
      tags,
      enabled_for_template_deployment,
      soft_delete_retention_days
    ]
  }
}

resource "azurerm_key_vault_key" "base_custom_kv_key" {
  depends_on = [azurerm_private_endpoint.base_custom_kv_pes, local.keys_depend_on, azurerm_key_vault.base_custom_kv]
  count      = local.use_custom_key_vault && !var.is_hub_staging? 1 : 0

  name            = "key-custom-${random_string.kvname.result}"
  key_vault_id    = local.custom_base_key_vault_id
  key_type        = "RSA-HSM"
  key_size        = 2048
  # expiration_date = timeadd(timestamp(), "87600h")

  rotation_policy {
    automatic {
      time_after_creation = "P1Y"
    }
  }

  key_opts = [
    "decrypt",
    "encrypt",
    "unwrapKey",
    "wrapKey",
  ]
  lifecycle {
    ignore_changes = [
      expiration_date,
      rotation_policy
    ]
  }
}

resource "azurerm_private_endpoint" "base_custom_kv_pes" {
  depends_on = [azurerm_key_vault.base_custom_kv]
  count      = var.public_keyvaults == false && local.use_custom_key_vault && !local.is_client? 1 : 0

  name                = "pep-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-kv-custom"
  location            = azurerm_resource_group.secr_rg[0].location
  resource_group_name = azurerm_resource_group.secr_rg[0].name
  subnet_id           = azurerm_subnet.subnets[local.pe_subnet_name].id

  private_service_connection {
    name                           = "base-kv-privateserviceconnection"
    private_connection_resource_id = local.custom_base_key_vault_id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]

    precondition {
      condition     = (var.is_spoke && length(local.all_subnets) > 0) || !var.is_spoke
      error_message = "No subnets found! Spokes require at least one subnet for base resource private endpoints. Set `is_spoke = false` to prevent building base spoke resources."
    }
  }
  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.vaultcore.azure.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }

}


resource "azurerm_key_vault" "base_kv" {
  depends_on = [local.peering_resources]
  count      = var.is_spoke && local.build_base_resources ? 1 : 0

  name                          = local.random_kv_names ? "kv-${var.application_id}${random_string.kvname.result}" : "kv-${var.line_of_business}${var.application_id}${local.env_region}"
  location                      = azurerm_resource_group.secr_rg[0].location
  resource_group_name           = azurerm_resource_group.secr_rg[0].name
  enabled_for_disk_encryption   = true
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days    = 90
  purge_protection_enabled      = true
  enable_rbac_authorization     = true
  public_network_access_enabled = var.public_keyvaults
  sku_name                      = "premium"
  network_acls {
    default_action = var.public_keyvaults ? "Allow" : "Deny"
    bypass         = "AzureServices"
  }

  tags = merge(local.all_tags, { soft-delete : 90, base : true })

  lifecycle {
    ignore_changes = [
      tags,
      enabled_for_template_deployment,
      soft_delete_retention_days,
      name
    ]
  }
}

resource "azurerm_key_vault_key" "base_kv_key" {
  depends_on = [time_sleep.dns_propagation, local.keys_depend_on]
  count      = var.is_spoke && !var.is_hub_staging ? 1 : 0

  name            = local.random_kv_names ? "key-${var.application_id}-${var.location}-${var.environment}${random_string.kvname.result}" : "key-${var.application_id}-${var.location}-${var.environment}"
  key_vault_id    = local.base_kv_id
  key_type        = "RSA-HSM"
  key_size        = 2048
  expiration_date = null # timeadd(timestamp(), "87600h")

  rotation_policy {
      automatic {
        time_after_creation = "P1Y"
      }
  }

  key_opts = [
    "decrypt",
    "encrypt",
    "unwrapKey",
    "wrapKey",
  ]
  
  lifecycle {
    ignore_changes = [
      expiration_date,
      rotation_policy
    ]
  }
}

resource "time_sleep" "dns_propagation" {
  depends_on      = [azurerm_private_endpoint.base_kv_pep]
  count           = var.public_keyvaults != true && length(azurerm_key_vault.base_kv) > 0 ? 1 : 0
  create_duration = "3m"
}

resource "azurerm_private_endpoint" "base_kv_pep" {
  count               = var.public_keyvaults == false && var.is_spoke && !local.is_client ? 1 : 0
  name                = "pep-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-base-kv"
  location            = azurerm_resource_group.secr_rg[0].location
  resource_group_name = azurerm_resource_group.secr_rg[0].name
  subnet_id           = azurerm_subnet.subnets[local.pe_subnet_name].id

  private_service_connection {
    name                           = "base-kv-privateserviceconnection"
    private_connection_resource_id = local.base_kv_id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]

    precondition {
      condition     = (var.is_spoke && length(local.all_subnets) > 0) || !var.is_spoke
      error_message = "No subnets found! Spokes require at least one subnet for base resource private endpoints. Set `is_spoke = false` to prevent building base spoke resources."
    }
  }
  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.vaultcore.azure.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }

}

# resource "null_resource" "delete_base_kv_pep_dns_when_destroyed" {
#   for_each = { for pep in azurerm_private_endpoint.base_kv_pep : pep.name => pep }
#   triggers = {
#     working_dir    = local.script_dir
#     delete_command = local.dns_command_delete
#     hostname       = "${split(".", each.value.custom_dns_configs[0].fqdn)[0]}.privatelink.vaultcore.azure.net"
#     ip_address     = each.value.private_service_connection[0].private_ip_address
#   }

#   provisioner "local-exec" {
#     when        = destroy
#     working_dir = self.triggers.working_dir
#     command     = self.triggers.delete_command
#     environment = {
#       LABEL = self.triggers.hostname
#       IP       = self.triggers.ip_address
#     }
#   }
# }

resource "azurerm_key_vault" "aks_de_keyvault" {
  depends_on = [local.peering_resources]

  count = local.aks_subnet_name != null ? 1 : 0

  name                          = var.random_kv_names ? "kv-${var.application_id}${random_string.kvname.result}aksde" : "kv-${var.line_of_business}${var.application_id}${local.env_region}aksde"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.aks_rg[0].name
  enabled_for_disk_encryption   = true
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days    = 7
  purge_protection_enabled      = true
  enable_rbac_authorization     = true
  public_network_access_enabled = var.public_keyvaults
  sku_name                      = "premium"
  network_acls {
    default_action = var.public_keyvaults ? "Allow" : "Deny"
    bypass         = "AzureServices"
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags,
      enabled_for_template_deployment
    ]
  }
}


resource "azurerm_private_endpoint" "aks_de_keyvault_pep" {
  count = local.aks_subnet_name != null && var.public_keyvaults == false ? 1 : 0

  name                = "pep-${var.line_of_business}${var.application_id}${local.env_region}aksde-kv"
  location            = azurerm_resource_group.aks_rg[0].location
  resource_group_name = azurerm_resource_group.aks_rg[0].name
  subnet_id           = var.aks_cluster.subnet_name != null ? azurerm_subnet.subnets[var.aks_cluster.subnet_name].id : local.aks_subnet_name

  private_service_connection {
    name                           = "aks-de-kv-privateserviceconnection"
    private_connection_resource_id = azurerm_key_vault.aks_de_keyvault[0].id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  provisioner "local-exec" {
    when        = create
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.vaultcore.azure.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }
}

# resource "null_resource" "delete_aksde_kv_pep_dns_when_destroyed" {
#   count = local.aks_subnet_name != null && var.public_keyvaults == false ? 1 : 0
#   triggers = {
#     working_dir    = local.script_dir
#     delete_command = local.dns_command_delete
#     hostname       = "${split(".", azurerm_private_endpoint.aks_de_keyvault_pep[0].custom_dns_configs[0].fqdn)[0]}.privatelink.vaultcore.azure.net"
#     ip_address     = azurerm_private_endpoint.aks_de_keyvault_pep[0].private_service_connection[0].private_ip_address
#   }

#   provisioner "local-exec" {
#     when        = destroy
#     working_dir = self.triggers.working_dir
#     command     = self.triggers.delete_command
#     environment = {
#       LABEL = self.triggers.hostname
#       IP       = self.triggers.ip_address
#     }
#   }
# }


resource "azurerm_key_vault" "aks_int_keyvault" {
  depends_on = [local.peering_resources]

  count = local.aks_subnet_name != null && var.aks_cluster.key_vault_secrets_provider ? 1 : 0

  name                          = var.random_kv_names ? "kv-${var.application_id}${random_string.kvname.result}aks" : "kv-${var.line_of_business}${var.application_id}${local.env_region}aks"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.aks_rg[0].name
  enabled_for_disk_encryption   = true
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days    = 7
  purge_protection_enabled      = true
  enable_rbac_authorization     = true
  public_network_access_enabled = var.public_keyvaults
  sku_name                      = "premium"

  network_acls {
    default_action = var.public_keyvaults ? "Allow" : "Deny"
    bypass         = "AzureServices"
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags,
      enabled_for_template_deployment
    ]
  }
}
resource "azurerm_private_endpoint" "aks_int_keyvault_pep" {
  count = local.aks_subnet_name != null && var.public_keyvaults == false && var.aks_cluster.key_vault_secrets_provider ? 1 : 0

  name                = "pep-${var.line_of_business}${var.application_id}${local.env_region}aks-kv"
  location            = azurerm_resource_group.aks_rg[0].location
  resource_group_name = azurerm_resource_group.aks_rg[0].name
  subnet_id           = var.aks_cluster.subnet_name != null ? azurerm_subnet.subnets[var.aks_cluster.subnet_name].id : local.aks_subnet_name

  private_service_connection {
    name                           = "aks-int-kv-privateserviceconnection"
    private_connection_resource_id = azurerm_key_vault.aks_int_keyvault[0].id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  # private_dns_zone_group {
  #   name = "default"
  #   private_dns_zone_ids = [azurerm_private_dns_zone.private_dns_zones["privatelink-vaultcore-azure-net"].id]
  # }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
  provisioner "local-exec" {
    working_dir = local.script_dir
    command     = local.dns_command_add

    environment = {
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.vaultcore.azure.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }
}

# resource "null_resource" "delete_aksint_kv_pep_dns_when_destroyed" {
#   count = local.aks_subnet_name != null && var.public_keyvaults == false && var.aks_cluster.key_vault_secrets_provider ? 1 : 0
#   triggers = {
#     working_dir    = local.script_dir
#     delete_command = local.dns_command_delete
#     hostname       = "${split(".", azurerm_private_endpoint.aks_int_keyvault_pep[0].custom_dns_configs[0].fqdn)[0]}.privatelink.vaultcore.azure.net"
#     ip_address     = azurerm_private_endpoint.aks_int_keyvault_pep[0].private_service_connection[0].private_ip_address
#   }

#   provisioner "local-exec" {
#     when        = destroy
#     working_dir = self.triggers.working_dir
#     command     = self.triggers.delete_command
#     environment = {
#       LABEL = self.triggers.hostname
#       IP       = self.triggers.ip_address
#     }
#   }
# }

locals {
  peering_resources = [azurerm_virtual_network_peering.spoke_to_hub, azurerm_virtual_network_peering.hub_to_spoke, azurerm_virtual_network_peering.hub_eastus2_to_spoke, azurerm_virtual_network_peering.hub_centralus_to_spoke]
  keys_depend_on    = [time_sleep.dns_propagation, local.peering_resources, azurerm_subnet_route_table_association.route_table_subnet_association, azurerm_route.routes]
}

resource "azurerm_key_vault_key" "aks_key_vault_key" {
  depends_on = [azurerm_private_endpoint.aks_de_keyvault_pep, local.keys_depend_on]
  count      = local.aks_subnet_name != null ? 1 : 0

  name         = var.random_kv_names ? "key-${var.line_of_business}${var.application_id}${var.environment}${random_string.kvname.result}aks" : "key-${var.line_of_business}${var.application_id}${var.environment}${local.short_location_name}aks"
  key_vault_id = azurerm_key_vault.aks_de_keyvault[0].id
  key_type     = "RSA-HSM"
  key_size     = 2048

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]

  lifecycle {
    ignore_changes = [
      key_type
    ]
  }
}

resource "azurerm_key_vault_secret" "aks_windows_password" {
  count = local.aks_subnet_name != null && var.aks_cluster.network_plugin == "azure" ? 1 : 0

  name         = "windows-password"
  value        = random_password.aks_windows_password[0].result
  key_vault_id = azurerm_key_vault.aks_de_keyvault[0].id
}

resource "azurerm_disk_encryption_set" "base_kv_des" {
  depends_on = [azurerm_private_endpoint.base_kv_pep, local.keys_depend_on]
  count      = var.is_spoke && !var.is_hub_staging ? 1 : 0

  name                = "des-${var.application_id}-${var.location}-${var.environment}"
  location            = azurerm_resource_group.secr_rg[0].location
  resource_group_name = azurerm_resource_group.secr_rg[0].name
  key_vault_key_id    = local.base_key_id

  identity {
    type = "SystemAssigned"
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }

}

resource "azurerm_disk_encryption_set" "base_kv_custom_des" {
  depends_on = [azurerm_private_endpoint.base_custom_kv_pes, local.keys_depend_on]
  count      = local.use_custom_key_vault && !var.is_hub_staging? 1 : 0

  name                = "des-custom-${var.application_id}-${var.location}-${var.environment}"
  location            = azurerm_resource_group.secr_rg[0].location
  resource_group_name = azurerm_resource_group.secr_rg[0].name
  key_vault_key_id    = azurerm_key_vault_key.base_custom_kv_key[0].id

  identity {
    type = "SystemAssigned"
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }

}


# Refer wiki for enabling key vault access for COSMOS DB via user assigned managed identity
# https://learn.microsoft.com/en-us/azure/cosmos-db/how-to-setup-customer-managed-keys

# Create User Assigned Managed Identity
resource "azurerm_user_assigned_identity" "base_kv_uai" {
  count = var.is_spoke ? 1 : 0

  location            = azurerm_resource_group.secr_rg[0].location
  resource_group_name = azurerm_resource_group.secr_rg[0].name
  # location                    = azurerm_resource_group.app.location
  name = "identity-${var.application_id}-${var.environment}"

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags,
      name
    ]
  }
}

resource "azurerm_role_assignment" "base_kv_key_access_aes_role" {
  count = var.is_spoke && !var.is_hub_staging ? 1 : 0

  scope                = local.base_kv_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_disk_encryption_set.base_kv_des[0].identity.0.principal_id
}

resource "azurerm_role_assignment" "base_custom_kv_key_access_aes_role" {
  count      = local.use_custom_key_vault && !var.is_hub_staging? 1 : 0

  scope                = local.custom_base_key_vault_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_disk_encryption_set.base_kv_custom_des[0].identity.0.principal_id
}

# Assign the user role on the Key vault to the Managed Identity.
resource "azurerm_role_assignment" "base_kv_key_access_aes_role_managed_identity" {
  count = var.is_spoke && !var.is_hub_staging ? 1 : 0

  scope                = local.base_kv_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.base_kv_uai[0].principal_id
}

# Assign the user role on the Key vault to the Managed Identity.
resource "azurerm_role_assignment" "base_custom_kv_key_access_aes_role_managed_identity" {
  count      = local.use_custom_key_vault && !var.is_hub_staging? 1 : 0

  scope                = local.custom_base_key_vault_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.base_kv_uai[0].principal_id
}

resource "time_sleep" "base_kv_role_propagation" {
  depends_on      = [azurerm_role_assignment.base_kv_key_access_aes_role_managed_identity]
  count           = var.is_spoke && !var.is_hub_staging ? 1 : 0
  create_duration = "30s"
}

resource "azurerm_role_assignment" "base_kv_key_access_user_role" {
  for_each             = toset(var.kv_user)
  scope                = local.base_kv_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = each.key
}

resource "azurerm_role_assignment" "base_kv_key_access_admin_role" {
  for_each             = toset(var.kv_admin)
  scope                = local.base_kv_id
  role_definition_name = "Key Vault Administrator"
  principal_id         = each.key
}

resource "azurerm_role_assignment" "base_kv_key_access_reader_role" {
  for_each             = toset(var.kv_reader)
  scope                = local.base_kv_id
  role_definition_name = "Key Vault Reader"
  principal_id         = each.key
}

resource "azurerm_role_assignment" "base_kv_access_cog_role" {
  for_each             = { for cog in var.cognitive_services : cog.name => cog }
  scope                = azurerm_cognitive_account.cogs["${each.value.name}"].id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_user_assigned_identity.base_kv_uai[0].principal_id
}
resource "azurerm_monitor_diagnostic_setting" "diag_ud_key_vaults" {
  for_each = { for kv in var.key_vaults : kv.name => kv }

  name                           = "diag-${azurerm_key_vault.ud_key_vaults[each.key].name}"
  target_resource_id             = azurerm_key_vault.ud_key_vaults[each.key].id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  storage_account_id             = var.diag_storage_account_id
  partner_solution_id            = var.partner_solution_id
  eventhub_authorization_rule_id = local.eventhub_info[local.region_environment].eventhub_authorization_rule_id
  eventhub_name                  = local.eventhub_info[local.region_environment].eventhub_name

  # this enables the Audit Logging on the KV
  enabled_log {
    category_group = "audit"

    retention_policy {
      enabled = false
    }
  }

  # if metrics are not enabled, this must be ignored because it will show up as a change on every run
  lifecycle {
    ignore_changes = [metric]
  }


}

resource "azurerm_monitor_diagnostic_setting" "diag_base_custom_kv" {
  count      = local.use_custom_key_vault && local.build_base_resources ? 1 : 0

  name                           = "diag-custom"
  target_resource_id             = azurerm_key_vault.base_custom_kv[0].id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  storage_account_id             = var.diag_storage_account_id
  partner_solution_id            = var.partner_solution_id
  eventhub_authorization_rule_id = local.eventhub_info[local.region_environment].eventhub_authorization_rule_id
  eventhub_name                  = local.eventhub_info[local.region_environment].eventhub_name

  # this enables the Audit Logging on the KV
  enabled_log {
    category_group = "audit"

    retention_policy {
      enabled = false
    }
  }

  # if metrics are not enabled, this must be ignored because it will show up as a change on every run
  lifecycle {
    ignore_changes = [metric]
  }

}

resource "azurerm_monitor_diagnostic_setting" "diag_base_kv" {
  count = var.is_spoke && local.build_base_resources ? 1 : 0

  name                           = "diag-${azurerm_key_vault.base_kv[count.index].name}"
  target_resource_id             = azurerm_key_vault.base_kv[count.index].id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  storage_account_id             = var.diag_storage_account_id
  partner_solution_id            = var.partner_solution_id
  eventhub_authorization_rule_id = local.eventhub_info[local.region_environment].eventhub_authorization_rule_id
  eventhub_name                  = local.eventhub_info[local.region_environment].eventhub_name

  # this enables the Audit Logging on the KV
  enabled_log {
    category_group = "audit"

    retention_policy {
      enabled = false
    }
  }

  # if metrics are not enabled, this must be ignored because it will show up as a change on every run
  lifecycle {
    ignore_changes = [metric]
  }

}


resource "azurerm_monitor_diagnostic_setting" "diag_aks_de_keyvault" {
  count = local.aks_subnet_name != null ? 1 : 0

  name                           = "diag-${azurerm_key_vault.aks_de_keyvault[count.index].name}"
  target_resource_id             = azurerm_key_vault.aks_de_keyvault[count.index].id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  storage_account_id             = var.diag_storage_account_id
  partner_solution_id            = var.partner_solution_id
  eventhub_authorization_rule_id = local.eventhub_info[local.region_environment].eventhub_authorization_rule_id
  eventhub_name                  = local.eventhub_info[local.region_environment].eventhub_name

  # this enables the Audit Logging on the KV
  enabled_log {
    category_group = "audit"

    retention_policy {
      enabled = false
    }
  }

  # if metrics are not enabled, this must be ignored because it will show up as a change on every run
  lifecycle {
    ignore_changes = [metric]
  }

}

resource "azurerm_monitor_diagnostic_setting" "diag_aks_int_keyvault" {
  count = local.aks_subnet_name != null && var.aks_cluster.key_vault_secrets_provider ? 1 : 0

  name                           = "diag-${azurerm_key_vault.aks_int_keyvault[count.index].name}"
  target_resource_id             = azurerm_key_vault.aks_int_keyvault[count.index].id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  storage_account_id             = var.diag_storage_account_id
  partner_solution_id            = var.partner_solution_id
  eventhub_authorization_rule_id = local.eventhub_info[local.region_environment].eventhub_authorization_rule_id
  eventhub_name                  = local.eventhub_info[local.region_environment].eventhub_name

  # this enables the Audit Logging on the KV
  enabled_log {
    category_group = "audit"

    retention_policy {
      enabled = false
    }
  }

  # if metrics are not enabled, this must be ignored because it will show up as a change on every run
  lifecycle {
    ignore_changes = [metric]
  }

}