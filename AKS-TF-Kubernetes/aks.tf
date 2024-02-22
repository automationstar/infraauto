resource "azurerm_kubernetes_cluster" "aks" {
  name                = format("%s-aks", var.short_prefix)
  location            = azurerm_resource_group.rg_aks.location
  resource_group_name = azurerm_resource_group.rg_aks.name
  dns_prefix          = "${var.prefix}-aks"

  kubernetes_version = var.kube_version

  default_node_pool {
    name            = "nodepool1"
    vm_size         = var.node_size
    node_count      = var.node_count
    vnet_subnet_id  = azurerm_subnet.subnet_aks.id
    enable_auto_scaling = true
    min_count       = 1
    max_count       = 3
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = var.network_plugin
    network_policy = var.network_policy
  }

  role_based_access_control {
    enabled = true
    azure_active_directory {
      managed = true
      admin_group_object_ids = [var.aad_admin_group_object_id]
    }
  }

  tags = {
    Environment = var.environment
  }
}
