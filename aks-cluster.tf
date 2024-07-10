locals {
  private_dns_zone_map = {
    "eastus2_prod"   = "/subscriptions/59b2cd00-9406-4a41-a772-e073dbe19796/resourceGroups/rg-cvsbloxhubuse2/providers/Microsoft.Network/privateDnsZones/privatelink.eastus2.azmk8s.io"
    "centralus_prod" = "/subscriptions/29ea5d6f-8539-4a95-8198-ca801994cbdb/resourceGroups/rg-cvsbloxhubusc/providers/Microsoft.Network/privateDnsZones/privatelink.centralus.azmk8s.io"
    #ALL VALUES BELOW NEED UPDATE; PLACEHOLDERS
    "eastus_prod"   = "/subscriptions/59b2cd00-9406-4a41-a772-e073dbe19796/resourceGroups/rg-cvsbloxhubuse2/providers/Microsoft.Network/privateDnsZones/privatelink.eastus.azmk8s.io"
    "westus3_prod" = "/subscriptions/29ea5d6f-8539-4a95-8198-ca801994cbdb/resourceGroups/rg-cvsbloxhubusc/providers/Microsoft.Network/privateDnsZones/privatelink.westus3.azmk8s.io"
    "eastus2_nonprod"   = "/subscriptions/59b2cd00-9406-4a41-a772-e073dbe19796/resourceGroups/rg-cvsbloxhubuse2/providers/Microsoft.Network/privateDnsZones/privatelink.eastus2.azmk8s.io"
    "centralus_nonprod" = "/subscriptions/29ea5d6f-8539-4a95-8198-ca801994cbdb/resourceGroups/rg-cvsbloxhubusc/providers/Microsoft.Network/privateDnsZones/privatelink.centralus.azmk8s.io"
    "eastus_nonprod"   = "/subscriptions/59b2cd00-9406-4a41-a772-e073dbe19796/resourceGroups/rg-cvsbloxhubuse2/providers/Microsoft.Network/privateDnsZones/privatelink.eastus.azmk8s.io"
    "westus3_nonprod" = "/subscriptions/29ea5d6f-8539-4a95-8198-ca801994cbdb/resourceGroups/rg-cvsbloxhubusc/providers/Microsoft.Network/privateDnsZones/privatelink.westus3.azmk8s.io"
    #ALL VALUES ABOVE NEED UPDATE; PLACEHOLDERS
  }
  private_dns_zone_id  = local.private_dns_zone_map[local.region_environment]
  aks_subnet_name_list = [for subnet in local.all_subnets : subnet.name if subnet.type == "aks" && subnet.name == var.aks_cluster.subnet_name]
  aks_subnet_name      = length(local.aks_subnet_name_list) != 0 ? local.aks_subnet_name_list[0] : var.aks_cluster.external_subnet_id != null ? var.aks_cluster.external_subnet_id : null

  external_mi_federated_credentials = {
    for fc in var.aks_federated_credentials : "fc-${fc.name}" => fc if fc.external_managed_identity_name != null && fc.user_defined_managed_identity_name == null
  }


   // Check if AKS cluster configuration is defined and if subnet_name is provided
  is_aks_configured = var.aks_cluster != null && var.aks_cluster.subnet_name != null

  // Validate subnet to see if it matches the AKS cluster's subnet_name
  validate_subnet_name = local.is_aks_configured ? [
    for subnet in var.subnets :
      subnet.name == var.aks_cluster.subnet_name
  ] : [true] // Default to true if AKS cluster configuration or subnet_name is not provided

  // Validate each subnet to see if the type is aks
  validate_subnet_type = local.is_aks_configured ? [
    for subnet in var.subnets :
    subnet.name == var.aks_cluster.subnet_name ? subnet.type == "aks" : false
  ] : [true] // Default to true if AKS cluster configuration or subnet_name is not provided

// Check if there is exactly one matching subnet and one maching type for AKS configuration
  is_valid_aks_subnet_name  = local.is_aks_configured ? length([for validation_result in local.validate_subnet_name : validation_result if validation_result == true]) == 1 : true
  is_valid_aks_subnet_type  = local.is_aks_configured ? length([for validation_result in local.validate_subnet_type : validation_result if validation_result == true]) == 1 : true

// spit error message for incorrect configurations for each validation
  final_validation_subnet_name = local.is_valid_aks_subnet_name ? true : tobool("${local.ec_error_aheader}${local.ec_error_subnet_name}${local.ec_error_zfooter}")
  final_validation_subnet_type = local.is_valid_aks_subnet_name && !local.is_valid_aks_subnet_type ? tobool("${local.ec_error_aheader}${local.ec_error_subnet_type}${local.ec_error_zfooter}") : true

}

resource "random_password" "aks_windows_password" {
  count   = local.aks_subnet_name != null && var.aks_cluster.network_plugin == "azure" ? 1 : 0
  length  = 20
  special = true
}

resource "azurerm_user_assigned_identity" "aks_managed_identity" {
  count = local.aks_subnet_name != null ? 1 : 0

  name                = "mi-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-aks"
  resource_group_name = azurerm_resource_group.aks_rg[0].name
  location            = var.location
  tags                = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_disk_encryption_set" "aks_disk_encryption_set" {
  depends_on = [azurerm_private_endpoint.aks_de_keyvault_pep, local.keys_depend_on]
  count      = local.aks_subnet_name != null ? 1 : 0

  name                = "des-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-aks"
  resource_group_name = azurerm_resource_group.aks_rg[0].name
  location            = var.location
  key_vault_key_id    = azurerm_key_vault_key.aks_key_vault_key[0].id
  tags                = local.all_tags

  identity {
    type = "SystemAssigned"
  }
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "random_string" "aks_suffix_name" {
  count   = var.aks_cluster.random_suffix ? 1 : 0
  length  = 3
  special = false
  upper   = false
}

resource "azurerm_kubernetes_cluster" "aks_cluster" {
  count = local.aks_subnet_name != null ? 1 : 0

  name                = var.aks_cluster.index != null ? "aks-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${var.aks_cluster.index}" : var.aks_cluster.random_suffix ? "aks-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${random_string.aks_suffix_name[0].result}" : "aks-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}"
  resource_group_name = azurerm_resource_group.aks_rg[0].name
  location            = var.location
  node_resource_group = "rg-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-aksnodes"

  sku_tier               = var.aks_cluster.sku_tier == "Paid" ? "Standard" : var.aks_cluster.sku_tier
  disk_encryption_set_id = azurerm_disk_encryption_set.aks_disk_encryption_set[0].id
  kubernetes_version     = var.aks_cluster.kubernetes_version != "" ? var.aks_cluster.kubernetes_version : null

  dns_prefix                        = "aks${var.line_of_business}${var.application_id}${var.environment}${local.short_location_name}"
  private_dns_zone_id               = local.private_dns_zone_id
  private_cluster_enabled           = true
  azure_policy_enabled              = true
  role_based_access_control_enabled = true
  local_account_disabled            = var.aks_cluster.local_account_disabled


  azure_active_directory_role_based_access_control {
    managed                = true
    admin_group_object_ids = concat(["75132e4d-8042-478c-b8da-75368be6c456"], var.aks_cluster.cluster_admin_group_object_ids)
    azure_rbac_enabled     = true
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks_managed_identity[0].id]
  }

  default_node_pool {
    vnet_subnet_id               = var.aks_cluster.external_subnet_id != null ? var.aks_cluster.external_subnet_id : azurerm_subnet.subnets["${var.aks_cluster.subnet_name}"].id
    name                         = var.aks_default_node_pool.name
    enable_auto_scaling          = var.aks_default_node_pool.enable_auto_scaling
    max_count                    = var.aks_default_node_pool.enable_auto_scaling ? var.aks_default_node_pool.max_count : null
    min_count                    = var.aks_default_node_pool.enable_auto_scaling ? var.aks_default_node_pool.min_count : null
    node_count                   = var.aks_default_node_pool.node_count
    vm_size                      = var.aks_default_node_pool.vm_size
    zones                        = var.aks_default_node_pool.zones
    max_pods                     = var.aks_default_node_pool.max_pods
    only_critical_addons_enabled = var.aks_default_node_pool.only_critical_addons_enabled
    orchestrator_version         = var.aks_default_node_pool.orchestrator_version
    node_taints                  = var.aks_default_node_pool.node_taints
    enable_host_encryption       = var.aks_default_node_pool.enable_host_encryption
    temporary_name_for_rotation  = "ectemppool"
  }

  network_profile {
    network_plugin = var.aks_cluster.network_plugin
    outbound_type  = "userDefinedRouting"
    service_cidr   = var.aks_cluster.network_plugin == "kubenet" ? "100.64.0.0/12" : null
    dns_service_ip = var.aks_cluster.network_plugin == "kubenet" ? "100.64.0.4" : null
    # docker_bridge_cidr = var.aks_cluster.network_plugin == "kubenet" ? "100.80.0.0/12" : null
    pod_cidr = var.aks_cluster.network_plugin == "kubenet" ? "100.96.0.0/11" : null
  }

  dynamic "windows_profile" {
    for_each = var.aks_cluster.network_plugin == "azure" ? [1] : []
    content {
      admin_username = "azureuser"
      admin_password = random_password.aks_windows_password[0].result
    }
  }

  # TODO: AGIC
  # ingress_application_gateway {
  #   enabled = var.ingress_application_gateway
  #   gateway_id = var.ingress_application_gateway ? azurerm_application_gateway.agic_app_gateway[0].id : null
  # }
  dynamic "key_vault_secrets_provider" {
    for_each = var.aks_cluster.key_vault_secrets_provider ? [1] : []
    content {
      secret_rotation_enabled  = var.aks_cluster.key_vault_secrets_provider_secret_rotation_enabled
      secret_rotation_interval = var.aks_cluster.key_vault_secrets_provider_secret_rotation_interval
    }
  }

  open_service_mesh_enabled = var.aks_cluster.open_service_mesh_enabled
  oidc_issuer_enabled       = var.aks_cluster.workload_identity_enabled
  workload_identity_enabled = var.aks_cluster.workload_identity_enabled

  dynamic "web_app_routing" {
    for_each = (var.aks_cluster.web_app_routing_enabled_preview && var.aks_cluster.key_vault_secrets_provider) ? [1] : []
    content {
      dns_zone_id = "" # Required but leaving as empty because CVS internal DNS is used instead of Azure DNS
    }
  }

  dynamic "oms_agent" {
    for_each = var.log_analytics_workspace != "none" || var.aks_cluster.external_log_analytics_workspace_resource_id != null ? [1] : []
    content {
      log_analytics_workspace_id = var.aks_cluster.external_log_analytics_workspace_resource_id != null ? var.aks_cluster.external_log_analytics_workspace_resource_id : azurerm_log_analytics_workspace.log_analytics_workspace[0].id
    }
  }

  depends_on = [azurerm_role_assignment.dns_zone_permissions, azurerm_role_assignment.azure_disk_encryption_permissions]

  # provisioner "local-exec" {
  #   when        = create
  #   working_dir = "${path.module}/scripts"
  #   command     = "chmod +x azlogin_oidc.sh; ./azlogin_oidc.sh; chmod +x argocd.sh; ./argocd.sh add $SUBSCRIPTION_ID $CLUSTER_RG $CLUSTER_NAME $ARGO_URL $ARGO_AUTH_TOKEN $GH_TOKEN"

  #   environment = {
  #     SUBSCRIPTION_ID = split("/", data.azurerm_subscription.current.id)[2]
  #     CLUSTER_RG      = azurerm_resource_group.aks_rg[0].name
  #     CLUSTER_NAME    = azurerm_kubernetes_cluster.aks_cluster[0].name
  #   }
  # }

  # provisioner "local-exec" {
  #   when        = destroy
  #   working_dir = "${path.module}/scripts"
  #   command     = "chmod +x azlogin_oidc.sh; ./azlogin_oidc.sh; chmod +x argocd.sh; ./argocd.sh rm $SUBSCRIPTION_ID $CLUSTER_RG $CLUSTER_NAME $ARGO_URL $ARGO_AUTH_TOKEN $GH_TOKEN"

  #   environment = {
  #     SUBSCRIPTION_ID = split("/", self.id)[2]
  #     CLUSTER_RG      = self.resource_group_name
  #     CLUSTER_NAME    = self.name
  #   }
  # }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
}
}

resource "null_resource" "argocd_setup" {
  depends_on = [azurerm_kubernetes_cluster.aks_cluster[0], azurerm_kubernetes_cluster_node_pool.extra_nodepools, azurerm_role_assignment.ec_apply_sp_cluster_admin_assignment]
  count = local.aks_subnet_name != null && !var.aks_cluster.legacy_argo ? 1 : 0

  triggers = {
    subscription_id = split("/", data.azurerm_subscription.current.id)[2]
    cluster_rg      = azurerm_resource_group.aks_rg[0].name
    cluster_name    = azurerm_kubernetes_cluster.aks_cluster[0].name
    private_fqdn    = azurerm_kubernetes_cluster.aks_cluster[0].private_fqdn
  }

  provisioner "local-exec" {
    when        = create
    working_dir = "${path.module}/scripts"
    command     = "chmod +x azlogin_oidc.sh; ./azlogin_oidc.sh; chmod +x argocd.sh; ./argocd.sh add $SUBSCRIPTION_ID $CLUSTER_RG $CLUSTER_NAME $PRIVATE_FQDN $ARGO_URL $ARGO_AUTH_TOKEN $GH_TOKEN"

    environment = {
      SUBSCRIPTION_ID = split("/", data.azurerm_subscription.current.id)[2]
      CLUSTER_RG      = azurerm_resource_group.aks_rg[0].name
      CLUSTER_NAME    = azurerm_kubernetes_cluster.aks_cluster[0].name
      PRIVATE_FQDN    = azurerm_kubernetes_cluster.aks_cluster[0].private_fqdn
    }
  }

  provisioner "local-exec" {
    when        = destroy
    working_dir = "${path.module}/scripts"
    command     = "chmod +x azlogin_oidc.sh; ./azlogin_oidc.sh; chmod +x argocd.sh; ./argocd.sh rm $SUBSCRIPTION_ID $CLUSTER_RG $CLUSTER_NAME $PRIVATE_FQDN $ARGO_URL $ARGO_AUTH_TOKEN $GH_TOKEN"

    environment = {
      SUBSCRIPTION_ID = self.triggers.subscription_id
      CLUSTER_RG      = self.triggers.cluster_rg
      CLUSTER_NAME    = self.triggers.cluster_name
      PRIVATE_FQDN    = self.triggers.private_fqdn
    }
  }

}

resource "null_resource" "nginx_opt_out_flag_cluster_yaml_input" {
  depends_on = [null_resource.argocd_setup]
  count      = var.aks_cluster.web_app_routing_enabled_preview ? 1 : 0

  triggers = {
    cluster_name = azurerm_kubernetes_cluster.aks_cluster[0].name
  }

  provisioner "local-exec" {
    when        = create
    working_dir = "${path.module}/scripts"
    command     = "chmod +x nginx_opt_out_cluster_yaml_input.sh; ./nginx_opt_out_cluster_yaml_input.sh add $CLUSTER_NAME"

    environment = {
      CLUSTER_NAME = self.triggers.cluster_name
    }
  }

  provisioner "local-exec" {
    when        = destroy
    working_dir = "${path.module}/scripts"
    command     = "chmod +x nginx_opt_out_cluster_yaml_input.sh; ./nginx_opt_out_cluster_yaml_input.sh rm $CLUSTER_NAME"

    environment = {
      CLUSTER_NAME = self.triggers.cluster_name
    }
  }
}

resource "null_resource" "delete_remaining_workload_identity_cluster_yaml_input_when_destroyed" {
  depends_on = [null_resource.argocd_setup, null_resource.nginx_opt_out_flag_cluster_yaml_input]
  count      = length(var.aks_federated_credentials) > 0 ? 1 : 0

  triggers = {
    cluster_name = azurerm_kubernetes_cluster.aks_cluster[0].name
  }

  provisioner "local-exec" {
    when        = destroy
    working_dir = "${path.module}/scripts"
    command     = "chmod +x workload_identity_cluster_yaml_input.sh; ./workload_identity_cluster_yaml_input.sh rm $CLUSTER_NAME \"\" \"\""

    environment = {
      CLUSTER_NAME = self.triggers.cluster_name
    }
  }
}

# Add null resource to be triggered only when namespaces are no longer specified, which will remove all the remaining ones
resource "null_resource" "delete_remaining_namespaces_when_destroyed" {
  depends_on = [null_resource.argocd_setup, null_resource.nginx_opt_out_flag_cluster_yaml_input, null_resource.delete_remaining_workload_identity_cluster_yaml_input_when_destroyed]
  count      = length(var.aks_cluster.namespaces) > 0 ? 1 : 0

  triggers = {
    cluster_name = azurerm_kubernetes_cluster.aks_cluster[0].name
  }

  provisioner "local-exec" {
    when        = destroy
    working_dir = "${path.module}/scripts"
    command     = "chmod +x namespaces_cluster_yaml_input.sh; ./namespaces_cluster_yaml_input.sh rm $CLUSTER_NAME \"\""

    environment = {
      CLUSTER_NAME = self.triggers.cluster_name
    }
  }
}

resource "null_resource" "aks_namespaces" {
  depends_on = [null_resource.argocd_setup, null_resource.nginx_opt_out_flag_cluster_yaml_input, null_resource.delete_remaining_workload_identity_cluster_yaml_input_when_destroyed, null_resource.delete_remaining_namespaces_when_destroyed]
  count      = length(var.aks_cluster.namespaces) > 0 ? 1 : 0

  triggers = {
    cluster_name = azurerm_kubernetes_cluster.aks_cluster[0].name
    namespaces   = join(" ", var.aks_cluster.namespaces)
  }

  provisioner "local-exec" {
    when        = create
    working_dir = "${path.module}/scripts"
    command     = "chmod +x namespaces_cluster_yaml_input.sh; ./namespaces_cluster_yaml_input.sh add $CLUSTER_NAME \"$NAMESPACES\""

    environment = {
      CLUSTER_NAME = self.triggers.cluster_name
      NAMESPACES   = self.triggers.namespaces
      
    }
  }


  # Destroys are performed on every update that removes a previously specified namespace, so no need for it anymore
  # provisioner "local-exec" {
  #   when        = destroy
  #   working_dir = "${path.module}/scripts"
  #   command     = "chmod +x namespaces_cluster_yaml_input.sh; ./namespaces_cluster_yaml_input.sh rm $CLUSTER_NAME \"$NAMESPACES\""

  #   environment = {
  #     CLUSTER_NAME    = self.triggers.cluster_name
  #     NAMESPACES      = self.triggers.namespaces
  #   }
  # }
}

resource "null_resource" "aks_webapprouting_ilb" {
  count      = var.aks_cluster.web_app_routing_enabled_preview ? 1 : 0
  depends_on = [azurerm_kubernetes_cluster.aks_cluster]

  triggers = {
    subscription_id = split("/", data.azurerm_subscription.current.id)[2]
    cluster_rg      = azurerm_resource_group.aks_rg[0].name
    cluster_name    = azurerm_kubernetes_cluster.aks_cluster[0].name
  }

  provisioner "local-exec" {
    when        = create
    working_dir = "${path.module}/scripts"
    command     = "chmod +x azlogin_oidc.sh; ./azlogin_oidc.sh; chmod +x aks_web_app_routing_ilb.sh; ./aks_web_app_routing_ilb.sh $SUBSCRIPTION_ID $CLUSTER_RG $CLUSTER_NAME"

    environment = {
      SUBSCRIPTION_ID = self.triggers.subscription_id
      CLUSTER_RG      = self.triggers.cluster_rg
      CLUSTER_NAME    = self.triggers.cluster_name
    }
  }
}

data "azurerm_user_assigned_identity" "webapprouting_managed_identity" {
  depends_on = [azurerm_kubernetes_cluster.aks_cluster]
  count      = local.aks_subnet_name != null && var.aks_cluster.web_app_routing_enabled_preview ? 1 : 0

  name                = "webapprouting-${azurerm_kubernetes_cluster.aks_cluster[0].name}"
  resource_group_name = azurerm_kubernetes_cluster.aks_cluster[0].node_resource_group
}

resource "azurerm_kubernetes_cluster_node_pool" "extra_nodepools" {
  for_each = { for extra_node_pool in var.aks_extra_node_pools : extra_node_pool.name => extra_node_pool }

  kubernetes_cluster_id  = azurerm_kubernetes_cluster.aks_cluster[0].id
  vnet_subnet_id         = var.aks_cluster.external_subnet_id != null ? var.aks_cluster.external_subnet_id : azurerm_subnet.subnets["${var.aks_cluster.subnet_name}"].id
  name                   = each.value.name
  mode                   = each.value.mode #? each.value.mode : null
  enable_auto_scaling    = each.value.enable_auto_scaling
  max_count              = each.value.enable_auto_scaling ? each.value.max_count : null
  min_count              = each.value.enable_auto_scaling ? each.value.min_count : null
  node_count             = each.value.node_count
  os_type                = each.value.os_type
  vm_size                = each.value.vm_size
  zones                  = each.value.zones
  max_pods               = each.value.max_pods
  orchestrator_version   = each.value.orchestrator_version
  node_labels            = each.value.labels
  node_taints            = each.value.node_taints
  enable_host_encryption = each.value.enable_host_encryption

  dynamic "linux_os_config" {
    for_each = each.value.vm_max_map_count != null ? [1] : []
    content {
      sysctl_config {
        vm_max_map_count = each.value.vm_max_map_count
      }
    }
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

data "azurerm_resources" "federated_credential_managed_identities" {
  for_each            = local.external_mi_federated_credentials
  name                = each.value.external_managed_identity_name
  resource_group_name = each.value.external_managed_identity_resource_group
}

resource "azurerm_federated_identity_credential" "aks_mi_federated_credential" {
  depends_on = [azurerm_kubernetes_cluster.aks_cluster]
  for_each   = { for fc_key, federated_credential in var.aks_federated_credentials : fc_key => federated_credential }

  name                = "fc-${each.value.name}"
  resource_group_name = each.value.user_defined_managed_identity_name != null ? azurerm_user_assigned_identity.ud_managed_identity[each.value.user_defined_managed_identity_name].resource_group_name : each.value.external_managed_identity_resource_group
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks_cluster[0].oidc_issuer_url
  parent_id           = each.value.user_defined_managed_identity_name != null ? azurerm_user_assigned_identity.ud_managed_identity[each.value.user_defined_managed_identity_name].id : data.azurerm_resources.federated_credential_managed_identities["fc-${each.value.name}"].resources[0].id
  subject             = "system:serviceaccount:${each.value.kubernetes_namespace}:${each.value.kubernetes_service_account_name}"
}

locals {
  workload_identity_cluster_yaml_input_list       = [for fc in var.aks_federated_credentials : { name : fc.name, cluster_name : "aks-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}", managed_identity_client_id : azurerm_user_assigned_identity.ud_managed_identity[fc.user_defined_managed_identity_name].client_id, namespace : fc.kubernetes_namespace } if !fc.non_default]
  workload_identity_client_ids_cluster_yaml_input = join(" ", [for el in local.workload_identity_cluster_yaml_input_list : el.managed_identity_client_id])
  namespaces_for_workload_identity_yaml_input     = join(" ", [for el in local.workload_identity_cluster_yaml_input_list : el.namespace])
}

resource "null_resource" "workload_identity_cluster_yaml_input" {
  depends_on = [null_resource.argocd_setup, null_resource.nginx_opt_out_flag_cluster_yaml_input, null_resource.delete_remaining_workload_identity_cluster_yaml_input_when_destroyed, null_resource.delete_remaining_namespaces_when_destroyed, null_resource.aks_namespaces]
  count      = length(var.aks_federated_credentials) > 0 ? 1 : 0

  triggers = {
    cluster_name                = azurerm_kubernetes_cluster.aks_cluster[0].name
    namespaces                  = local.namespaces_for_workload_identity_yaml_input
    managed_identity_client_ids = local.workload_identity_client_ids_cluster_yaml_input
  }

  provisioner "local-exec" {
    when        = create
    working_dir = "${path.module}/scripts"
    command     = "chmod +x workload_identity_cluster_yaml_input.sh; ./workload_identity_cluster_yaml_input.sh add $CLUSTER_NAME \"$NAMESPACES\" \"$MANAGED_IDENTITY_CLIENT_IDS\""

    environment = {
      CLUSTER_NAME                = self.triggers.cluster_name
      NAMESPACES                  = self.triggers.namespaces
      MANAGED_IDENTITY_CLIENT_IDS = self.triggers.managed_identity_client_ids
    }
  }
}


resource "null_resource" "aks_loadBalancerIp" {
  depends_on = [null_resource.argocd_setup, null_resource.nginx_opt_out_flag_cluster_yaml_input, null_resource.delete_remaining_workload_identity_cluster_yaml_input_when_destroyed, null_resource.delete_remaining_namespaces_when_destroyed, null_resource.aks_namespaces, null_resource.workload_identity_cluster_yaml_input]
  count = var.is_spoke && local.aks_subnet_name != null && (var.aks_cluster.loadBalancerIp != "" || var.aks_cluster.auto_loadBalancerIp == true || var.aks_cluster.service_mesh == "istio") ? 1 : 0

  triggers = {
    cluster_name        = azurerm_kubernetes_cluster.aks_cluster[0].name
    resource_group_name = azurerm_subnet.subnets[local.aks_subnet_name].resource_group_name
    vnet_name           = azurerm_subnet.subnets[local.aks_subnet_name].virtual_network_name
    subnet_name         = azurerm_subnet.subnets[local.aks_subnet_name].name
    loadBalancerIp      = var.aks_cluster.loadBalancerIp
    service_mesh        = var.aks_cluster.service_mesh
    auto_loadBalancerIp = var.aks_cluster.loadBalancerIp == "" ? true : var.aks_cluster.auto_loadBalancerIp

  }

  provisioner "local-exec" {
    when        = create
    working_dir = "${path.module}/scripts"
    command = "chmod +x loadBalancerIp_cluster_yaml_input.sh; ./loadBalancerIp_cluster_yaml_input.sh add $CLUSTER_NAME \"$LOAD_BALANCER_IP\" \"$AUTO_LOAD_BALANCER_IP\" \"$RESOURCE_GROUP\" \"$VNET_NAME\" \"$SUBNET_NAME\" \"$SERVICE_MESH\""
    environment = {
      CLUSTER_NAME                      = self.triggers.cluster_name
      LOAD_BALANCER_IP                  = self.triggers.loadBalancerIp
      AUTO_LOAD_BALANCER_IP             = self.triggers.auto_loadBalancerIp
      RESOURCE_GROUP                    = self.triggers.resource_group_name
      VNET_NAME                         = self.triggers.vnet_name
      SUBNET_NAME                       = self.triggers.subnet_name
      SERVICE_MESH                      = self.triggers.service_mesh
     }
  }

  provisioner "local-exec" {
    when        = destroy
    working_dir = "${path.module}/scripts"
    command = "chmod +x loadBalancerIp_cluster_yaml_input.sh; ./loadBalancerIp_cluster_yaml_input.sh rm $CLUSTER_NAME  \"$LOAD_BALANCER_IP\" \"$AUTO_LOAD_BALANCER_IP\" \"$RESOURCE_GROUP\" \"$VNET_NAME\" \"$SUBNET_NAME\" \"$SERVICE_MESH\""
    environment = {
      CLUSTER_NAME                    = self.triggers.cluster_name
      LOAD_BALANCER_IP                = self.triggers.loadBalancerIp
      AUTO_LOAD_BALANCER_IP           = self.triggers.auto_loadBalancerIp 
      RESOURCE_GROUP                  = self.triggers.resource_group_name
      VNET_NAME                       = self.triggers.vnet_name
      SUBNET_NAME                     = self.triggers.subnet_name
      SERVICE_MESH                    = self.triggers.service_mesh
    }
  }
}

resource "null_resource" "istio_service_mesh" {
  depends_on = [null_resource.argocd_setup, null_resource.nginx_opt_out_flag_cluster_yaml_input, null_resource.delete_remaining_workload_identity_cluster_yaml_input_when_destroyed, null_resource.delete_remaining_namespaces_when_destroyed, null_resource.aks_namespaces, null_resource.workload_identity_cluster_yaml_input, null_resource.aks_loadBalancerIp]
  count = var.aks_cluster.service_mesh == "istio" ? 1 : 0

  triggers = {
    cluster_name = azurerm_kubernetes_cluster.aks_cluster[0].name
    service_mesh   = var.aks_cluster.service_mesh
  }

  provisioner "local-exec" {
    when        = create
    working_dir = "${path.module}/scripts"
    command     = "chmod +x istio_service_mesh_cluster_yaml_input.sh; ./istio_service_mesh_cluster_yaml_input.sh add $CLUSTER_NAME"
    environment = {
      CLUSTER_NAME     = self.triggers.cluster_name
    }
  }

  provisioner "local-exec" {
    when        = destroy
    working_dir = "${path.module}/scripts"
    command     = "chmod +x istio_service_mesh_cluster_yaml_input.sh; ./istio_service_mesh_cluster_yaml_input.sh rm $CLUSTER_NAME"
    environment = {
      CLUSTER_NAME     = self.triggers.cluster_name
    }
  }
}
