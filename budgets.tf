resource "azurerm_consumption_budget_resource_group" "azure_budget" {
  for_each          = { for budget in var.budgets : budget.name => budget }
  name              = each.key
  resource_group_id = each.value.resource_group_id != null ? each.value.resource_group_id : azurerm_resource_group.ud_rgs[each.value.resource_group].id

  amount     = each.value.amount
  time_grain = each.value.time_grain

  time_period {
    start_date = formatdate("${each.value.start_date}'T00:00:00Z'", timestamp())
    #  start_date = "2022-07-06T00:00:00Z"
    #  end_date   = "2022-07-01T00:00:00Z"
  }

  notification {
    enabled        = each.value.notify
    threshold      = each.value.threshold
    threshold_type = each.value.threshold_type
    operator       = "GreaterThan"

    contact_emails = each.value.emails != [] ? each.value.emails : [
      var.required_tags["sharedemailaddress"],
    ]
  }

  lifecycle {
    ignore_changes = [
      time_period[0].start_date,
      time_period[0].end_date
    ]
  }
}
