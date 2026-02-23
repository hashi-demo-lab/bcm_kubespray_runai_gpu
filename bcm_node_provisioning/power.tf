# BCM Node Provisioning Module - Power Actions
#
# Category assignment and IPMI power control via cmsh local-exec.
# Workaround for BCM provider bugs with interface types.
# Power actions are gated by var.enable_power_action for safety.

# ==========================================================================
# CATEGORY UPDATE — via cmsh (workaround for provider powerControl bug)
# ==========================================================================

resource "terraform_data" "category_update" {
  for_each = local.targeted_nodes

  triggers_replace = {
    category = each.value.category
  }

  provisioner "local-exec" {
    command = "cmsh -c 'device; use ${each.key}; set category ${each.value.category}; commit'"
  }
}

# ==========================================================================
# POWER ACTIONS — trigger via cmsh (local-exec workaround for provider bugs)
# ==========================================================================

locals {
  # Map Terraform power_action values to cmsh power commands
  cmsh_power_action_map = {
    "power_on"    = "on"
    "power_off"   = "off"
    "power_cycle" = "reset"
    "power_reset" = "reset"
    "reboot"      = "reset"
  }
  cmsh_power_action = local.cmsh_power_action_map[var.power_action]
  power_node_list   = join(",", keys(local.power_action_nodes))
}

resource "terraform_data" "power_action" {
  count = var.enable_power_action && length(local.power_action_nodes) > 0 ? 1 : 0

  depends_on = [terraform_data.category_update]

  triggers_replace = {
    action = var.power_action
    nodes  = local.power_node_list
  }

  provisioner "local-exec" {
    command = "cmsh -c 'device; power -n ${local.power_node_list} ${local.cmsh_power_action}'"
  }
}
