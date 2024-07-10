resource "azurerm_monitor_action_group" "ag" {
  for_each = { for ag in var.monitor_action_groups : ag.name => ag }

  name                = "ag${var.line_of_business}${var.application_id}${local.env_region}${each.key}"
  enabled             = true
  resource_group_name = azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name
  short_name          = length("ag${var.line_of_business}${var.application_id}${local.env_region}${each.key}") > 12 ? substr("ag${each.key}${var.line_of_business}${var.application_id}${local.env_region}", 0, 12) : "ag${var.line_of_business}${var.application_id}${local.env_region}${each.key}"
  tags                = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }

  dynamic "email_receiver" {
    for_each = [each.value.email_receiver]
    content {
      email_address           = email_receiver.value["email_address"]
      name                    = email_receiver.value["name"]
      use_common_alert_schema = try(email_receiver.value["use_common_alert_schema"], false)
    }
  }
}
