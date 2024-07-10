locals {
  queue_sender_permissions = flatten([
    for entity in var.service_bus_entities : [
      for identity in entity.queue_data_senders : {
        name                  = "queue_data_sender_${entity.name}_${identity}"
        principal_id          = identity
        scope                 = azurerm_servicebus_queue.queues["${entity.name}"].id
        service_bus_namespace = entity.namespace_name
      }
    ] if entity.type == "queue"
  ])

  queue_receiver_permissions = flatten([
    for entity in var.service_bus_entities : [
      for identity in entity.queue_data_receivers : {
        name                  = "queue_data_receiver_${entity.name}_${identity}"
        principal_id          = identity
        scope                 = azurerm_servicebus_queue.queues["${entity.name}"].id
        service_bus_namespace = entity.namespace_name
      }
    ] if entity.type == "queue"
  ])

  topic_sender_permissions = flatten([
    for entity in var.service_bus_entities : [
      for identity in entity.topic_data_senders : {
        name                  = "topic_data_sender_${entity.name}_${identity}"
        principal_id          = identity
        scope                 = azurerm_servicebus_topic.topics["${entity.name}"].id
        service_bus_namespace = entity.namespace_name
      }
    ] if entity.type == "topic"
  ])

  subscription_receiver_permissions = flatten([
    for subscription in var.service_bus_subscriptions : [
      for identity in subscription.subscription_data_receivers : {
        name                  = "subscription_data_receiver_${subscription.name}_${identity}"
        principal_id          = identity
        scope                 = azurerm_servicebus_subscription.subs["${subscription.name}"].id
        service_bus_namespace = subscription.namespace_name
      }
    ]
  ])

  list_of_service_bus_resources = concat(local.queue_sender_permissions, local.queue_receiver_permissions, local.subscription_receiver_permissions, local.topic_sender_permissions)

  principal_id_and_namespace_list = distinct(flatten([
    for serviceBusInfo in local.list_of_service_bus_resources : {
      name                  = "${serviceBusInfo.principal_id}_${serviceBusInfo.service_bus_namespace}"
      principal_id          = serviceBusInfo.principal_id
      service_bus_namespace = serviceBusInfo.service_bus_namespace
    }
  ]))
}

resource "azurerm_servicebus_namespace" "sb_ns" {
  for_each = { for sb_info in var.service_bus_namespace : sb_info.name => sb_info }

  name                          = "sb-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.value.name}"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.sb_rg[0].name
  sku                           = "Premium"
  capacity                      = each.value.capacity
  public_network_access_enabled = false
  zone_redundant                = each.value.is_zone_redundant
  local_auth_enabled            = each.value.local_auth_enabled
  minimum_tls_version           = "1.2"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.base_kv_uai[0].id]
  }
  dynamic "customer_managed_key" {
    for_each = each.value.infrastructure_encryption_enabled == false ? [1] : []
    content {
      key_vault_key_id = local.base_key_id
      identity_id      = azurerm_user_assigned_identity.base_kv_uai[0].id
    }
  }
  dynamic "customer_managed_key" {
    for_each = each.value.infrastructure_encryption_enabled ? [1] : []
    content {
      key_vault_key_id                  = local.base_key_id
      identity_id                       = azurerm_user_assigned_identity.base_kv_uai[0].id
      infrastructure_encryption_enabled = true
    }
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags,
      customer_managed_key
    ]
  }
  network_rule_set {
    trusted_services_allowed      = each.value.trusted_services_allowed
    public_network_access_enabled = false
  }
}

resource "azurerm_servicebus_queue" "queues" {
  for_each = { for sb_entity_info in var.service_bus_entities : sb_entity_info.name => sb_entity_info if sb_entity_info.type == "queue" }

  name         = "sbq-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.value.name}"
  namespace_id = azurerm_servicebus_namespace.sb_ns["${each.value.namespace_name}"].id

  max_message_size_in_kilobytes           = each.value.max_message_size_in_kilobytes
  max_size_in_megabytes                   = each.value.max_size_in_megabytes
  requires_duplicate_detection            = each.value.requires_duplicate_detection
  default_message_ttl                     = each.value.default_message_ttl
  duplicate_detection_history_time_window = each.value.duplicate_detection_history_time_window
  status                                  = each.value.status
  enable_batched_operations               = each.value.enable_batched_operations
  auto_delete_on_idle                     = each.value.auto_delete_on_idle
  enable_partitioning                     = each.value.enable_partitioning
  enable_express                          = each.value.enable_express
  lock_duration                           = each.value.lock_duration
  dead_lettering_on_message_expiration    = each.value.dead_lettering_on_message_expiration
  forward_to                              = each.value.forward_to
  forward_dead_lettered_messages_to       = each.value.forward_dead_lettered_messages_to
  requires_session                        = each.value.requires_session
  max_delivery_count                      = each.value.max_delivery_count
}

resource "azurerm_servicebus_topic" "topics" {
  for_each = { for sb_entity_info in var.service_bus_entities : sb_entity_info.name => sb_entity_info if sb_entity_info.type == "topic" }

  name         = "sbt-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.value.name}"
  namespace_id = azurerm_servicebus_namespace.sb_ns["${each.value.namespace_name}"].id

  max_message_size_in_kilobytes           = each.value.max_message_size_in_kilobytes
  max_size_in_megabytes                   = each.value.max_size_in_megabytes
  requires_duplicate_detection            = each.value.requires_duplicate_detection
  default_message_ttl                     = each.value.default_message_ttl
  duplicate_detection_history_time_window = each.value.duplicate_detection_history_time_window
  status                                  = each.value.status
  enable_batched_operations               = each.value.enable_batched_operations
  auto_delete_on_idle                     = each.value.auto_delete_on_idle
  enable_partitioning                     = each.value.enable_partitioning
  enable_express                          = each.value.enable_express
  support_ordering                        = each.value.support_ordering
}

resource "azurerm_servicebus_subscription" "subs" {
  for_each = { for subs_info in var.service_bus_subscriptions : subs_info.name => subs_info }

  name     = each.value.name
  topic_id = azurerm_servicebus_topic.topics["${each.value.topic_name}"].id

  max_delivery_count                        = each.value.max_delivery_count
  auto_delete_on_idle                       = each.value.auto_delete_on_idle
  default_message_ttl                       = each.value.default_message_ttl
  lock_duration                             = each.value.lock_duration
  status                                    = each.value.status
  requires_session                          = each.value.requires_session
  forward_to                                = each.value.forward_to
  forward_dead_lettered_messages_to         = each.value.forward_dead_lettered_messages_to
  enable_batched_operations                 = each.value.enable_batched_operations
  dead_lettering_on_message_expiration      = each.value.dead_lettering_on_message_expiration
  dead_lettering_on_filter_evaluation_error = each.value.dead_lettering_on_filter_evaluation_error
  client_scoped_subscription_enabled        = each.value.client_scoped_subscription_enabled

  dynamic "client_scoped_subscription" {
    for_each = each.value.client_scoped_subscription != null ? each.value.client_scoped_subscription : {}
    content {
      is_client_scoped_subscription_shareable = client_scoped_subscription.value.is_client_scoped_subscription_shareable
      is_client_scoped_subscription_durable   = client_scoped_subscription.value.is_client_scoped_subscription_durable
    }
  }
}

resource "azurerm_servicebus_subscription_rule" "sub_rules" {
  for_each = { for sub_rules in var.service_bus_subscription_rules : sub_rules.name => sub_rules }

  name            = each.value.name
  subscription_id = azurerm_servicebus_subscription.subs["${each.value.subscription_name}"].id

  filter_type = each.value.filter_type
  sql_filter  = each.value.sql_filter
  action      = each.value.action

  dynamic "correlation_filter" {
    for_each = each.value.filter_type == "CorrelationFilter" ? [1] : []
    content {
      correlation_id      = each.value.correlation_filter.correlation_id
      label               = each.value.correlation_filter.label
      properties          = each.value.correlation_filter.properties
      content_type        = each.value.correlation_filter.content_type
      message_id          = each.value.correlation_filter.message_id
      reply_to            = each.value.correlation_filter.reply_to
      reply_to_session_id = each.value.correlation_filter.reply_to_session_id
      session_id          = each.value.correlation_filter.session_id
      to                  = each.value.correlation_filter.to
    }
  }
}

resource "azurerm_private_endpoint" "ud_service_bus_pes" {
  for_each            = { for sb in var.service_bus_namespace : sb.name => sb if sb.subnet_name != null || sb.external_subnet_id != null }
  name                = "pep-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-sb-${each.value.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.sb_rg[0].name
  subnet_id           = each.value.external_subnet_id != null ? each.value.external_subnet_id : azurerm_subnet.subnets["${each.value.subnet_name}"].id

  private_service_connection {
    name                           = "${each.value.name}-privateserviceconnection"
    private_connection_resource_id = azurerm_servicebus_namespace.sb_ns["${each.value.name}"].id
    is_manual_connection           = false
    subresource_names              = ["namespace"]
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
      LABEL    = "${split(".", self.custom_dns_configs[0].fqdn)[0]}.privatelink.servicebus.windows.net"
      IP       = self.private_service_connection[0].private_ip_address
      HOSTNAME = self.custom_dns_configs[0].fqdn
    }
  }
}

resource "azurerm_servicebus_namespace_network_rule_set" "sb_ns_nr" {
  for_each                      = { for sb_info in var.service_bus_namespace : sb_info.name => sb_info }
  namespace_id                  = azurerm_servicebus_namespace.sb_ns["${each.value.name}"].id
  trusted_services_allowed      = each.value.trusted_services_allowed
  public_network_access_enabled = false
}
