

# Deploy MI permissions over virtual network
resource "azurerm_role_assignment" "virtual_network_permissions" {
  count                = local.aks_subnet_name != null ? 1 : 0
  scope                = var.aks_cluster.external_vnet_id != null ? var.aks_cluster.external_vnet_id : local.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_managed_identity[0].principal_id
}

# If using kubenet, Deploy MI permissions over route table
resource "azurerm_role_assignment" "route_table_permissions" {
  count                = local.aks_subnet_name != null && var.aks_cluster.network_plugin == "kubenet" ? 1 : 0
  scope                = var.aks_cluster.external_subnet_route_table_id != null ? var.aks_cluster.external_subnet_route_table_id : azurerm_route_table.route_tables["${var.aks_cluster.subnet_name}"].id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_managed_identity[0].principal_id
}

resource "azurerm_role_assignment" "resource_group_permissions" {
  count                = local.aks_subnet_name != null ? 1 : 0
  scope                = azurerm_resource_group.aks_rg[0].id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_managed_identity[0].principal_id
}

resource "azurerm_role_assignment" "dns_zone_permissions" {
  count                = local.aks_subnet_name != null ? 1 : 0
  scope                = local.private_dns_zone_id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_managed_identity[0].principal_id
}

resource "azurerm_role_assignment" "azure_disk_encryption_permissions" {
  count                = local.aks_subnet_name != null ? 1 : 0
  scope                = azurerm_key_vault.aks_de_keyvault[0].id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_disk_encryption_set.aks_disk_encryption_set[0].identity.0.principal_id
}

resource "azurerm_role_assignment" "key_vaults_secret_provider_permissions" {
  count                = local.aks_subnet_name != null && var.aks_cluster.key_vault_secrets_provider ? 1 : 0
  scope                = azurerm_key_vault.aks_int_keyvault[0].id
  role_definition_name = "Key Vault Administrator"
  principal_id         = azurerm_kubernetes_cluster.aks_cluster[0].key_vault_secrets_provider[0].secret_identity[0].object_id # ?  azurerm_kubernetes_cluster.aks_cluster.key_vault_secrets_provider[0].secret_identity.client_id : null
}

resource "azurerm_role_assignment" "key_vault_admin_permissions" {
  count                = local.aks_subnet_name != null && var.aks_cluster.key_vault_secrets_provider ? length(var.aks_cluster.key_vault_admin_group_object_ids) : 0
  scope                = azurerm_key_vault.aks_int_keyvault[0].id
  role_definition_name = "Key Vault Administrator"
  principal_id         = var.aks_cluster.key_vault_admin_group_object_ids[count.index]
}

resource "azurerm_role_assignment" "key_vault_web_app_routing_certificates_officer" {
  depends_on           = [azurerm_key_vault.aks_int_keyvault, data.azurerm_user_assigned_identity.webapprouting_managed_identity[0]]
  count                = local.aks_subnet_name != null && var.aks_cluster.web_app_routing_enabled_preview ? 1 : 0
  scope                = azurerm_key_vault.aks_int_keyvault[0].id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = data.azurerm_user_assigned_identity.webapprouting_managed_identity[0].principal_id

  lifecycle {
    ignore_changes = [principal_id]
  }
}

resource "azurerm_role_assignment" "key_vault_web_app_routing_secrets_user" {
  depends_on           = [azurerm_key_vault.aks_int_keyvault, data.azurerm_user_assigned_identity.webapprouting_managed_identity[0]]
  count                = local.aks_subnet_name != null && var.aks_cluster.web_app_routing_enabled_preview ? 1 : 0
  scope                = azurerm_key_vault.aks_int_keyvault[0].id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azurerm_user_assigned_identity.webapprouting_managed_identity[0].principal_id

  lifecycle {
    ignore_changes = [principal_id]
  }
}

resource "azurerm_role_assignment" "privileged_service_principal_resource_group_permissions" {
  count                = local.aks_subnet_name != null && var.aks_cluster.privileged_service_principal_object_id != "" ? 1 : 0
  scope                = azurerm_resource_group.aks_rg[0].id
  role_definition_name = "AKS Service Principal Operator"
  principal_id         = var.aks_cluster.privileged_service_principal_object_id
}

resource "azurerm_role_assignment" "privileged_service_principal_virtual_network_permissions" {
  count                = local.aks_subnet_name != null && var.aks_cluster.privileged_service_principal_object_id != "" ? 1 : 0
  scope                = var.aks_cluster.external_vnet_id != null ? var.aks_cluster.external_vnet_id : local.vnet_id
  role_definition_name = "AKS Service Principal Operator"
  principal_id         = var.aks_cluster.privileged_service_principal_object_id
}

resource "azurerm_role_assignment" "aks_acr_integration" {
  count                = local.aks_subnet_name != null ? 1 : 0
  scope                = "/subscriptions/59b2cd00-9406-4a41-a772-e073dbe19796/resourceGroups/rg-cvsacrhub000/providers/Microsoft.ContainerRegistry/registries/acrcvshub000"
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks_cluster[0].kubelet_identity[0].object_id
}

resource "azurerm_role_assignment" "app_acr_integration" {
  count                = local.aks_subnet_name != null && var.aks_cluster.acr_integration_id != "" ? 1 : 0
  scope                = var.aks_cluster.acr_integration_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks_cluster[0].kubelet_identity[0].object_id
}

resource "azurerm_role_assignment" "ud_acr_integration" {
  for_each             = local.aks_subnet_name != null ? { for container_registry in var.container_registry : container_registry.name => container_registry } : {}
  scope                = azurerm_container_registry.container_registry[each.value.name].id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks_cluster[0].kubelet_identity[0].object_id
}

resource "azurerm_role_assignment" "container_registry_ud_mi_container_registry_admin_acr_push_rbac" {
  depends_on           = [azurerm_user_assigned_identity.ud_managed_identity, azurerm_container_registry.container_registry]
  for_each             = { for permission in local.container_registry_ud_mi_container_registry_admin_permissions : permission.name => permission }
  scope                = each.value.scope
  role_definition_name = "AcrPush"
  principal_id         = each.value.principal_id
}

resource "azurerm_role_assignment" "container_registry_ud_mi_container_registry_admin_acr_pull_rbac" {
  depends_on           = [azurerm_user_assigned_identity.ud_managed_identity, azurerm_container_registry.container_registry]
  for_each             = { for permission in local.container_registry_ud_mi_container_registry_admin_permissions : permission.name => permission }
  scope                = each.value.scope
  role_definition_name = "AcrPull"
  principal_id         = each.value.principal_id
}

resource "azurerm_role_assignment" "container_registry_ud_mi_container_registry_admin_acr_delete_rbac" {
  depends_on           = [azurerm_user_assigned_identity.ud_managed_identity, azurerm_container_registry.container_registry]
  for_each             = { for permission in local.container_registry_ud_mi_container_registry_admin_permissions : permission.name => permission }
  scope                = each.value.scope
  role_definition_name = "AcrDelete"
  principal_id         = each.value.principal_id
}

resource "azurerm_role_assignment" "container_registry_ud_mi_container_registry_admin_acr_image_signer_rbac" {
  depends_on           = [azurerm_user_assigned_identity.ud_managed_identity, azurerm_container_registry.container_registry]
  for_each             = { for permission in local.container_registry_ud_mi_container_registry_admin_permissions : permission.name => permission }
  scope                = each.value.scope
  role_definition_name = "AcrImageSigner"
  principal_id         = each.value.principal_id
}

resource "azurerm_role_assignment" "ec_apply_sp_cluster_admin_assignment" {
  count                = local.aks_subnet_name != null ? 1 : 0
  scope                = azurerm_kubernetes_cluster.aks_cluster[0].id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = "5b73d199-58a8-43a1-8926-c03b04b9c24f"
}

resource "azurerm_role_assignment" "cluster_admin_group_permissions" {
  count                = length(var.aks_cluster.cluster_admin_group_object_ids)
  scope                = azurerm_kubernetes_cluster.aks_cluster[0].id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = var.aks_cluster.cluster_admin_group_object_ids[count.index]
}

resource "azurerm_role_assignment" "cluster_admin_group_user_permissions" {
  count                = length(var.aks_cluster.cluster_admin_group_object_ids)
  scope                = azurerm_kubernetes_cluster.aks_cluster[0].id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = var.aks_cluster.cluster_admin_group_object_ids[count.index]
}

resource "azurerm_role_assignment" "cluster_writer_group_permissions" {
  count                = length(var.aks_cluster.cluster_writer_group_object_ids)
  scope                = azurerm_kubernetes_cluster.aks_cluster[0].id
  role_definition_name = "Azure Kubernetes Service RBAC Writer"
  principal_id         = var.aks_cluster.cluster_writer_group_object_ids[count.index]
}

resource "azurerm_role_assignment" "cluster_writer_group_user_permissions" {
  count                = length(var.aks_cluster.cluster_writer_group_object_ids)
  scope                = azurerm_kubernetes_cluster.aks_cluster[0].id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = var.aks_cluster.cluster_writer_group_object_ids[count.index]
}

resource "azurerm_role_assignment" "cluster_reader_group_permissions" {
  count                = length(var.aks_cluster.cluster_reader_group_object_ids)
  scope                = azurerm_kubernetes_cluster.aks_cluster[0].id
  role_definition_name = "Azure Kubernetes Service RBAC Reader"
  principal_id         = var.aks_cluster.cluster_reader_group_object_ids[count.index]
}

resource "azurerm_role_assignment" "cluster_reader_group_user_permissions" {
  count                = length(var.aks_cluster.cluster_reader_group_object_ids)
  scope                = azurerm_kubernetes_cluster.aks_cluster[0].id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = var.aks_cluster.cluster_reader_group_object_ids[count.index]
}

resource "azurerm_role_assignment" "cluster_gha_managed_identity_user_permissions" {
  depends_on           = [azurerm_user_assigned_identity.ud_managed_identity, azurerm_kubernetes_cluster.aks_cluster]
  for_each             = { for permission in local.gha_aks_deploy_rbac : permission.identity_name => permission.name... }
  scope                = azurerm_kubernetes_cluster.aks_cluster[0].id
  role_definition_name = "Azure Kubernetes Service Cluster User Role"
  principal_id         = azurerm_user_assigned_identity.ud_managed_identity[each.key].principal_id
}

resource "azurerm_role_assignment" "cluster_gha_managed_identity_cluster_admin_permissions" {
  depends_on           = [azurerm_user_assigned_identity.ud_managed_identity, azurerm_kubernetes_cluster.aks_cluster]
  for_each             = toset([for fc in var.gha_federated_credentials : fc.user_defined_managed_identity_name if fc.cluster_admin == true])
  scope                = azurerm_kubernetes_cluster.aks_cluster[0].id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = azurerm_user_assigned_identity.ud_managed_identity[each.value].principal_id
}

resource "azurerm_role_assignment" "cluster_gha_managed_identity_namespace_deploy_permissions" {
  depends_on           = [azurerm_user_assigned_identity.ud_managed_identity, azurerm_kubernetes_cluster.aks_cluster]
  for_each             = { for permission in local.gha_aks_deploy_rbac : permission.name => permission }
  scope                = "${azurerm_kubernetes_cluster.aks_cluster[0].id}/namespaces/${each.value.namespace}"
  role_definition_name = "Azure Kubernetes Service RBAC Admin" # Azure Kubernetes Service RBAC Writer does not give permission over Kubernetes CRDs
  principal_id         = azurerm_user_assigned_identity.ud_managed_identity[each.value.identity_name].principal_id
}

resource "azurerm_role_assignment" "servicebus_queue_sender_permissions" {
  for_each             = { for permission in local.queue_sender_permissions : permission.name => permission }
  scope                = each.value.scope
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = each.value.principal_id
}

resource "azurerm_role_assignment" "servicebus_namespace_reader_permissions" {
  for_each             = { for permission in local.principal_id_and_namespace_list : permission.name => permission }
  scope                = azurerm_servicebus_namespace.sb_ns["${each.value.service_bus_namespace}"].id
  role_definition_name = "Reader"
  principal_id         = each.value.principal_id
}

resource "azurerm_role_assignment" "servicebus_queue_receiver_permissions" {
  for_each             = { for permission in local.queue_receiver_permissions : permission.name => permission }
  scope                = each.value.scope
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = each.value.principal_id
}

resource "azurerm_role_assignment" "servicebus_topic_sender_permissions" {
  for_each             = { for permission in local.topic_sender_permissions : permission.name => permission }
  scope                = each.value.scope
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = each.value.principal_id
}

resource "azurerm_role_assignment" "servicebus_subscription_receiver_permissions" {
  for_each             = { for permission in local.subscription_receiver_permissions : permission.name => permission }
  scope                = each.value.scope
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = each.value.principal_id
}


resource "azurerm_role_assignment" "ud_keyvault_secrets_user_rbac" {
  for_each             = { for permission in local.ud_key_vault_secrets_user_permissions : permission.name => permission }
  scope                = each.value.scope
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value.principal_id
}

resource "azurerm_role_assignment" "ud_keyvault_ud_mi_secrets_user_rbac" {
  depends_on           = [azurerm_user_assigned_identity.ud_managed_identity, azurerm_key_vault.ud_key_vaults]
  for_each             = { for permission in local.ud_key_vault_ud_mi_secrets_user_permissions : permission.name => permission }
  scope                = each.value.scope
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.ud_managed_identity[each.value.ud_mi_name].principal_id
}

resource "azurerm_role_assignment" "ud_keyvault_crypto_user_rbac" {
  for_each             = { for permission in local.ud_key_vault_crypto_user_permissions : permission.name => permission }
  scope                = each.value.scope
  role_definition_name = "Key Vault Crypto User"
  principal_id         = each.value.principal_id
}

resource "azurerm_role_assignment" "ud_keyvault_ud_mi_crypto_user_rbac" {
  depends_on           = [azurerm_user_assigned_identity.ud_managed_identity, azurerm_key_vault.ud_key_vaults]
  for_each             = { for permission in local.ud_key_vault_ud_mi_crypto_user_permissions : permission.name => permission }
  scope                = each.value.scope
  role_definition_name = "Key Vault Crypto User"
  principal_id         = each.value.principal_id
}

resource "azurerm_role_assignment" "ud_key_vault_secrets_officer_rbac" {
  for_each             = { for permission in local.ud_key_vault_admin_permissions : permission.name => permission }
  scope                = each.value.scope
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value.principal_id
}

resource "azurerm_role_assignment" "ud_key_vault_certificates_officer_rbac" {
  for_each             = { for permission in local.ud_key_vault_admin_permissions : permission.name => permission }
  scope                = each.value.scope
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = each.value.principal_id
}

resource "azurerm_role_assignment" "ud_keyvault_ud_mi_key_vault_admin_secrets_officer_rbac" {
  depends_on           = [azurerm_user_assigned_identity.ud_managed_identity, azurerm_key_vault.ud_key_vaults]
  for_each             = { for permission in local.ud_key_vault_ud_mi_key_vault_admin_permissions : permission.name => permission }
  scope                = each.value.scope
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value.principal_id
}

resource "azurerm_role_assignment" "ud_keyvault_ud_mi_key_vault_admin_certificates_officer_rbac" {
  depends_on           = [azurerm_user_assigned_identity.ud_managed_identity, azurerm_key_vault.ud_key_vaults]
  for_each             = { for permission in local.ud_key_vault_ud_mi_key_vault_admin_permissions : permission.name => permission }
  scope                = each.value.scope
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = each.value.principal_id
}

resource "azurerm_role_assignment" "ud_keyvault_ud_mi_key_vault_admin_crypto_officer_rbac" {
  depends_on           = [azurerm_user_assigned_identity.ud_managed_identity, azurerm_key_vault.ud_key_vaults]
  for_each             = { for permission in local.ud_key_vault_ud_mi_key_vault_admin_permissions : permission.name => permission }
  scope                = each.value.scope
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = each.value.principal_id
}

locals {
  rbac_assignment_list = fileexists("rbac.csv") ? csvdecode(file("rbac.csv")) : []
}

resource "azurerm_role_assignment" "ud_rbac_assignments" {
  for_each             = { for rbac in local.rbac_assignment_list : rbac.name => rbac }
  scope                = each.value.scope
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
}
