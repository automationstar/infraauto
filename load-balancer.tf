locals {
  lb_list = var.load_balancers
  backend_pool_addresses = flatten([
    for lb in var.load_balancers : [
      for pooladdress in lb.backend_pool.ip_addresses : {
        ip_address        = pooladdress
        lb_name                     = lb.name
      }
    ]
  ])
  health_probes = flatten([
    for lb in var.load_balancers : [
      for probe in lb.health_probes : {
        lb_name = lb.name
        name = probe.name
        port = probe.port
        protocol = probe.protocol
        threshold = probe.probe_threshold
        interval = probe.interval
      }
    ]

  ])
  lb_rules = flatten([
    for lb in var.load_balancers : [
      for rule in lb.lb_rules : {
        lb_name = lb.name
        name    = rule.name
        frontend_port = rule.frontend_port
        backend_port = rule.backend_port
        backend_pool_names = rule.backend_pool_names
        health_probe = rule.health_probe
        frontend_config_name = rule.frontend_config_name
        protocol = rule.protocol

      }
    ]
  ])
}

# Create Azure Load Balancer

resource "azurerm_lb" "alb" {
  for_each = { for lb in local.lb_list : lb.name => lb if lb.sku == "Standard" }

  name                = "lbi-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.key}"
  location            = var.location
  resource_group_name = azurerm_resource_group.ud_rgs["${each.value.ud_resource_group}"].name
  sku = each.value.sku
  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }

  frontend_ip_configuration {
    name                 = "fe-${each.key}"
    private_ip_address_allocation = each.value.frontend_ip_config.is_dynamic_ip ? "Dynamic" : "Static"
    private_ip_address = each.value.frontend_ip_config.ip_address
    subnet_id = azurerm_subnet.subnets["${each.value.frontend_ip_config.subnet}"].id
  }
}



resource "azurerm_lb_backend_address_pool" "lb_pool" {
  for_each = { for lb in local.backend_pool_addresses : lb.lb_name => lb... }
  loadbalancer_id = azurerm_lb.alb["${each.key}"].id
  name = "bep-${each.key}"
}

resource "azurerm_lb_backend_address_pool_address" "bepa" {
  for_each = { for lb in local.backend_pool_addresses : lb.ip_address => lb }
  name = "bepa-${each.key}"
  backend_address_pool_id = azurerm_lb_backend_address_pool.lb_pool["${each.value.lb_name}"].id
  virtual_network_id = local.vnet_id
  ip_address = each.key
}


resource "azurerm_lb_probe" "lb_probe" {
  for_each = { for lb in local.health_probes : lb.name => lb }
  loadbalancer_id = azurerm_lb.alb["${each.value.lb_name}"].id
  name = "lbpro-${each.value.name}"
  port = "${each.value.port}"
  protocol = each.value.protocol
  probe_threshold = each.value.threshold
  interval_in_seconds = each.value.interval
}

resource "azurerm_lb_rule" "lb_rule" {
  for_each = { for lb in local.lb_rules : lb.name => lb }
  loadbalancer_id = azurerm_lb.alb["${each.value.lb_name}"].id
  name = "lbrule-${each.value.name}"
  protocol = each.value.protocol


  frontend_port = each.value.frontend_port
  backend_port = each.value.backend_port
  disable_outbound_snat = true
  frontend_ip_configuration_name = "fe-${each.value.lb_name}"
  probe_id = azurerm_lb_probe.lb_probe["${each.value.health_probe}"].id
  backend_address_pool_ids = [azurerm_lb_backend_address_pool.lb_pool["${each.value.lb_name}"].id]

}



