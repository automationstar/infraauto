# locals {
#   cog_locations = {
#     "CustomVision.Training" = "eastus2"
#     "CustomVision.Prediction" = "eastus2"
#     "OpenAI"       = "eastus"
#   }
#   cog_prefixes = keys(local.cog_locations)
# }

resource "azurerm_cognitive_account" "cogs" {
  depends_on = [time_sleep.cog_kv_role_propagation]
  for_each   = { for cog_info in var.cognitive_services : cog_info.name => cog_info }

  name                          = "cog-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.value.name}"
  resource_group_name           = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name : azurerm_resource_group.cog_rg[0].name
  location                      = each.value.location
  sku_name                      = each.value.sku_name
  kind                          = each.value.kind
  custom_subdomain_name         = each.value.custom_subdomain != null ? each.value.custom_subdomain : "${lower("${var.line_of_business}${var.application_id}${var.environment}${local.short_location_name}${each.value.name}")}"
  public_network_access_enabled = false
  fqdns                         = each.value.fqdns
  local_auth_enabled            = each.value.local_auth_enabled

  tags = each.value.ai_governance_tag != null ? merge(local.all_tags, { ai_governance = "${each.value.ai_governance_tag}" }) : local.all_tags
  lifecycle {
    ignore_changes = [
      tags,
      outbound_network_access_restricted,
      customer_managed_key["key_vault_key_id"]
    ]

    precondition {
      condition = lower(each.value.kind) == "openai" ? each.value.ai_governance_tag != null || lookup(var.optional_tags, "ai_governance", null) != null : true
      error_message = "OpenAI instances require an ai governance tag. Either provide a value for 'ai_governance_tag' on this Cognitive Service definition, or provide an 'ai_governance' tag in optional_tags."
    }
  }
  
  dynamic "identity" {
    for_each = !contains(split(".", each.value.kind), "CustomVision") ? [1] : []
    content {
      type         = "SystemAssigned, UserAssigned"
      identity_ids = [azurerm_user_assigned_identity.cog_kv_uai[each.value.location].id]
    }
  }

  dynamic "identity" {
    for_each = contains(split(".", each.value.kind), "CustomVision") ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  dynamic "storage" {
    for_each = each.value.storage_account_id != null || each.value.storage_account_name != null ? [1] : []
    content {
      storage_account_id = each.value.storage_account_id != null ? each.value.storage_account_id : each.value.storage_account_name != null ? azurerm_storage_account.ud_storage_accounts[each.value.storage_account_name].id : null
      identity_client_id = each.value.storage_identity_id != null ? each.value.storage_identity_id : each.value.storage_account_name != null ? azurerm_user_assigned_identity.base_kv_uai[0].client_id : null
    }
  }
  network_acls {
    default_action = "Deny"
    virtual_network_rules {
      subnet_id = each.value.external_subnet_id != null ? each.value.external_subnet_id : azurerm_subnet.subnets[each.value.subnet_name].id
    }
  }

  dynamic "customer_managed_key" {
    for_each = !contains(split(".", each.value.kind), "CustomVision") ? [1] : []
    content {
      key_vault_key_id   = azurerm_key_vault_key.cog_kv_key[each.value.location].id
      identity_client_id = azurerm_user_assigned_identity.cog_kv_uai[each.value.location].client_id
    }
  }

  provisioner "local-exec" {
    when        = create
    working_dir = "${path.module}/scripts"
    command = (
      each.value.kind == "OpenAI" ?
      "chmod +x azlogin_oidc.sh; ./azlogin_oidc.sh; chmod +x openai_dlp.sh; ./openai_dlp.sh $SUBSCRIPTION_ID $RESOURCE_ID" : "/bin/true"
    )
    environment = {
      SUBSCRIPTION_ID = "${split("/", data.azurerm_subscription.current.id)[2]}"
      RESOURCE_ID     = "${self.id}"
    }
  }
}


resource "time_sleep" "openai_dlp_propagation" {
  depends_on = [azurerm_cognitive_account.cogs]
  count      = length([for cog_info in var.cognitive_services : cog_info.name if cog_info.kind == "OpenAI"])

  create_duration = "2m"
}

resource "azurerm_cognitive_account_customer_managed_key" "cog_cmk" {
  depends_on = [azurerm_private_endpoint.cog_peps, azurerm_role_assignment.cog_kv_key_access_cv_role_managed_identity]
  for_each   = { for cog_info in var.cognitive_services : cog_info.name => cog_info if contains(split(".", cog_info.kind), "CustomVision") }

  cognitive_account_id = azurerm_cognitive_account.cogs[each.key].id
  key_vault_key_id     = azurerm_key_vault_key.cog_kv_key[each.value.location].id

}
resource "azurerm_monitor_diagnostic_setting" "diag_cog" {
  for_each = { for cog_info in var.cognitive_services : cog_info.name => cog_info }

  name                           = "diag-${azurerm_cognitive_account.cogs[each.key].name}"
  target_resource_id             = azurerm_cognitive_account.cogs[each.key].id
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

locals {
  validate_cog_has_service_endpoints = [for cog in var.cognitive_services : azurerm_subnet.subnets[cog.subnet_name].service_endpoints != null ? !contains(azurerm_subnet.subnets[cog.subnet_name].service_endpoints, "Microsoft.CognitiveServices") ? tobool("${local.ec_error_aheader}${local.ec_error_cog_no_se}${cog.subnet_name}${local.ec_error_zfooter}") : true : tobool("${local.ec_error_aheader}${local.ec_error_cog_no_se}${cog.subnet_name}${local.ec_error_zfooter}")]
}

resource "azurerm_private_endpoint" "cog_peps" {
  depends_on          = [time_sleep.openai_dlp_propagation]
  for_each            = { for cog_info in var.cognitive_services : cog_info.name => cog_info }
  name                = "pep-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.value.name}"
  location            = var.location
  resource_group_name = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name : azurerm_resource_group.cog_rg[0].name
  subnet_id           = each.value.external_subnet_id != null ? each.value.external_subnet_id : azurerm_subnet.subnets[each.value.subnet_name].id
  #azurerm_subnet.subnets[each.value.subnet_name].id : azurerm_subnet.subnets[local.pe_subnet_name].id

  private_service_connection {
    name                           = "${each.value.name}-privateserviceconnection"
    private_connection_resource_id = azurerm_cognitive_account.cogs[each.value.name].id
    is_manual_connection           = false
    subresource_names              = ["account"]
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
      LABEL    = each.value.kind == "OpenAI" ? "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.openai.azure.com" : "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.cognitiveservices.azure.com"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }
}

# resource "null_resource" "delete_cog_pep_dns_when_destroyed" {
#   for_each = { for cog_info in var.cognitive_services : cog_info.name => cog_info }
#   triggers = {
#     working_dir    = local.script_dir
#     delete_command = local.dns_command_delete
#     hostname       = each.value.kind == "OpenAI" ? "${split(".", azurerm_private_endpoint.cog_peps[each.value.name].custom_dns_configs[0].fqdn)[0]}.privatelink.openai.azure.com" : "${split(".", azurerm_private_endpoint.cog_peps[each.value.name].custom_dns_configs[0].fqdn)[0]}.privatelink.cognitiveservices.azure.com"
#     ip_address     = azurerm_private_endpoint.cog_peps[each.value.name].private_service_connection[0].private_ip_address
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
  locations_needing_keys = length(var.cognitive_services) > 0 ? distinct([for cog in var.cognitive_services : cog.location]) : []
  location_name_code_map = {
    "eastus2"        = "01"
    "centralus"      = "02"
    "northcentralus" = "03"
    "eastus"         = "04"
    "westus3"        = "05"
  }
}

resource "azurerm_key_vault" "cog_kv" {
  depends_on = [local.peering_resources]

  for_each = toset(local.locations_needing_keys)

  name                          = var.random_kv_names && index(local.locations_needing_keys, each.value) == 0 ? "kv-cog${var.line_of_business}${var.application_id}${random_string.kvname.result}" : var.random_kv_names ? "kv-cog${lookup(local.location_name_code_map, each.value, "99")}${var.application_id}${random_string.kvname.result}" : "kv-cog${var.line_of_business}${var.application_id}${local.env_region}${lookup(local.location_name_code_map, each.value, "99")}"
  location                      = each.value
  resource_group_name           = azurerm_resource_group.secr_rg[0].name
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
      enabled_for_template_deployment,
      name
    ]
  }
}

locals {
  cog_kvs = distinct(flatten([
    for cog in var.cognitive_services : [
      {
        subnet_id         = cog.external_subnet_id != null ? cog.external_subnet_id : null
        subnet_name       = cog.external_subnet_id == null ? cog.subnet_name : null
        name              = "${cog.subnet_name != null ? cog.subnet_name : cog.external_subnet_id}.${cog.location}"
        subnet_location   = cog.external_subnet_region != null ? cog.external_subnet_region : var.location
        cog_location      = cog.location
        ud_resource_group = cog.ud_resource_group != null ? cog.ud_resource_group : null
      }
    ]
  ]))
  unique_names = distinct([for kv in local.cog_kvs : kv.cog_location])
  cog_kvs_needing_peps = [
    for location in local.unique_names : (
      [for kv in local.cog_kvs : kv if kv.cog_location == location][0]
  )]
}

resource "azurerm_private_endpoint" "cog_kv_peps" {
  for_each            = { for kv in local.cog_kvs_needing_peps : kv.name => kv if var.public_keyvaults == false }
  name                = "pep-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.value.cog_location}-cogkv"
  location            = each.value.subnet_location
  resource_group_name = each.value.ud_resource_group != null ? azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name : azurerm_resource_group.cog_rg[0].name
  subnet_id           = each.value.subnet_id != null ? each.value.subnet_id : each.value.subnet_name != null ? azurerm_subnet.subnets[each.value.subnet_name].id : azurerm_subnet.subnets[local.pe_subnet_name].id

  private_service_connection {
    name                           = "${each.value.cog_location}-kv-privateserviceconnection"
    private_connection_resource_id = azurerm_key_vault.cog_kv[each.value.cog_location].id
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

# resource "null_resource" "delete_cog_kv_pep_dns" {
#   for_each            = { for kv in local.cog_kvs_needing_peps : kv.name => kv if var.public_keyvaults == false }
#   triggers = {
#     working_dir    = local.script_dir
#     delete_command = local.dns_command_delete
#     hostname       = "${split(".", azurerm_private_endpoint.cog_peps[each.key].custom_dns_configs[0].fqdn)[0]}.privatelink.vaultcore.azure.net"
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

resource "azurerm_monitor_diagnostic_setting" "diag_cog_kv" {
  for_each = toset([for locale in local.locations_needing_keys : locale if locale == "eastus2" || locale == "centralus"])

  name                           = "diag-${azurerm_key_vault.cog_kv[each.key].name}"
  target_resource_id             = azurerm_key_vault.cog_kv[each.key].id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  storage_account_id             = var.diag_storage_account_id
  partner_solution_id            = var.partner_solution_id
  eventhub_authorization_rule_id = local.eventhub_info["${each.key}_${local.routing_environment}"].eventhub_authorization_rule_id
  eventhub_name                  = local.eventhub_info["${each.key}_${local.routing_environment}"].eventhub_name

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

resource "azurerm_key_vault_key" "cog_kv_key" {
  for_each   = toset(local.locations_needing_keys)
  depends_on = [azurerm_private_endpoint.cog_kv_peps, local.keys_depend_on]

  name            = var.random_kv_names ? "key-cog-${var.application_id}-${var.location}-${var.environment}-${random_string.kvname.result}" : "key-cog-${var.application_id}-${var.location}-${var.environment}-${lookup(local.location_name_code_map, each.value, "99")}"
  key_vault_id    = azurerm_key_vault.cog_kv[each.value].id
  key_type        = "RSA-HSM"
  key_size        = 2048
  expiration_date = timeadd(timestamp(), "87600h")
  key_opts = [
    "decrypt",
    "encrypt",
    "unwrapKey",
    "wrapKey",
  ]
  lifecycle {
    ignore_changes = [
      expiration_date,
      name
    ]
  }

}

resource "azurerm_user_assigned_identity" "cog_kv_uai" {
  for_each = toset(local.locations_needing_keys)

  location            = each.value
  resource_group_name = azurerm_resource_group.secr_rg[0].name
  # location                    = azurerm_resource_group.app.location
  name = "identity-cog-${var.application_id}-${var.environment}-${lookup(local.location_name_code_map, each.value, "99")}"

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags,
      name
    ]
  }
}

resource "azurerm_role_assignment" "cog_kv_key_access_aes_role_managed_identity" {
  for_each             = toset(local.locations_needing_keys)
  scope                = azurerm_key_vault.cog_kv[each.value].id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.cog_kv_uai[each.value].principal_id
}

resource "azurerm_role_assignment" "cog_kv_key_access_cv_role_managed_identity" {
  for_each             = { for cog_info in var.cognitive_services : cog_info.name => cog_info if contains(split(".", cog_info.kind), "CustomVision") }
  scope                = azurerm_key_vault.cog_kv[each.value.location].id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_cognitive_account.cogs[each.key].identity[0].principal_id
}

resource "time_sleep" "cog_kv_role_propagation" {
  depends_on = [azurerm_role_assignment.cog_kv_key_access_aes_role_managed_identity]
  count      = length(local.locations_needing_keys) > 0 ? 1 : 0

  create_duration = "30s"
}

resource "azurerm_role_assignment" "cog_kv_access_cog_role" {
  for_each = { for cog_info in var.cognitive_services : cog_info.name => cog_info }

  scope                = azurerm_cognitive_account.cogs[each.value.name].id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_user_assigned_identity.cog_kv_uai[each.value.location].principal_id
}


resource "azurerm_cognitive_deployment" "models" {
  depends_on = [time_sleep.openai_dlp_propagation]
  for_each   = { for cog_info in var.cognitive_services : cog_info.name => cog_info if cog_info.model != null && cog_info.kind == "OpenAI" }

  name                 = "${each.key}-${each.value.model}"
  cognitive_account_id = azurerm_cognitive_account.cogs[each.key].id

  model {
    format  = "OpenAI"
    name    = each.value.model
    version = each.value.model_version
  }

  scale {
    type     = "Standard"
    capacity = each.value.capacity
  }

  lifecycle {
    ignore_changes = [
      rai_policy_name
    ]
  }

}

resource "azurerm_cognitive_deployment" "ud_models" {
  for_each = { for model in var.ai_models : model.name => model }

  name                 = "${each.value.ai_name}-${each.value.name}"
  cognitive_account_id = azurerm_cognitive_account.cogs[each.value.ai_name].id

  model {
    format  = "OpenAI"
    name    = each.value.model
    version = each.value.model_version
  }

  scale {
    type     = "Standard"
    capacity = each.value.capacity
  }

  lifecycle {
    ignore_changes = [
      rai_policy_name
    ]
  }

}

resource "azurerm_role_assignment" "openai_user_access" {
  for_each = { for cog_info in var.cognitive_services : cog_info.name => cog_info if cog_info.user_group != null && cog_info.kind == "OpenAI" }

  scope                = azurerm_cognitive_account.cogs[each.key].id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = each.value.user_group
}

resource "azurerm_role_assignment" "openai_cognitive_user_access" {
  for_each = { for cog_info in var.cognitive_services : cog_info.name => cog_info if cog_info.user_group != null && cog_info.kind == "OpenAI" }

  scope                = azurerm_cognitive_account.cogs[each.key].id
  role_definition_name = "Cognitive Services User"
  principal_id         = each.value.user_group
}
