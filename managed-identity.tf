locals {
  mi_with_env_info = { for mi in var.ud_managed_identities : mi.name => (mi.env != null) ? mi : merge(mi, { env = var.environment }) }

  gha_fc_environment_subject = [
    for fc in var.gha_federated_credentials :
    merge(fc, { subject = "repo:${fc.github_organization}/${fc.github_repository}:environment:${fc.github_entity_value}" })
    if fc.github_entity == "Environment"
  ]

  gha_fc_branch_subject = [
    for fc in var.gha_federated_credentials :
    merge(fc, { subject = "repo:${fc.github_organization}/${fc.github_repository}:ref:refs/heads/${fc.github_entity_value}" })
    if fc.github_entity == "Branch"
  ]

  gha_fc_pullrequest_subject = [
    for fc in var.gha_federated_credentials :
    merge(fc, { subject = "repo:${fc.github_organization}/${fc.github_repository}:pull_request" })
    if fc.github_entity == "Pull Request"
  ]

  gha_fc_tag_subject = [
    for fc in var.gha_federated_credentials :
    merge(fc, { subject = "repo:${fc.github_organization}/${fc.github_repository}:ref:refs/tags/${fc.github_entity_value}" })
    if fc.github_entity == "Tag"
  ]

  gha_fc_with_subject = concat(local.gha_fc_environment_subject, local.gha_fc_branch_subject, local.gha_fc_pullrequest_subject, local.gha_fc_tag_subject)

  gha_aks_deploy_rbac = flatten([
    for fc in var.gha_federated_credentials : [
      for namespace in fc.aks_deploy.namespaces : {
        name          = "${fc.name}-aks-${namespace}"
        identity_name = fc.user_defined_managed_identity_name
        namespace     = namespace
      } if local.aks_subnet_name != null
    ]
  ])
}

resource "azurerm_user_assigned_identity" "ud_managed_identity" {
  for_each = { for managed_identity in local.mi_with_env_info : managed_identity.name => managed_identity }

  name                = "mi-${var.line_of_business}-${var.application_id}-${each.value.env}-${local.short_location_name}-${each.key}"
  resource_group_name = each.value.resource_group != null ? azurerm_resource_group.ud_rgs[lower(each.value.resource_group)].name : each.value.resource_group_name == null ? azurerm_resource_group.mi_rg[0].name : each.value.resource_group_name
  location            = var.location

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_federated_identity_credential" "gha_mi_federated_credential" {
  depends_on = [azurerm_user_assigned_identity.ud_managed_identity]
  for_each   = { for federated_credential in local.gha_fc_with_subject : "fc-gha-${federated_credential.name}" => federated_credential }

  name                = "fc-gha-${each.value.name}"
  resource_group_name = azurerm_user_assigned_identity.ud_managed_identity[each.value.user_defined_managed_identity_name].resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  parent_id           = azurerm_user_assigned_identity.ud_managed_identity[each.value.user_defined_managed_identity_name].id
  subject             = each.value.subject
}
