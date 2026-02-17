# BCM Node Provisioning Module - Power Actions
#
# IPMI power control via cmsh local-exec.
# Power actions are gated by var.enable_power_action for safety.

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

  triggers_replace = {
    action    = var.power_action
    nodes     = local.power_node_list
    timestamp = timestamp()
  }

  provisioner "local-exec" {
    command = "cmsh -c 'device; power -n ${local.power_node_list} ${local.cmsh_power_action}'"
  }
}

# ==========================================================================
# NATIVE POWER ACTIONS — requires Terraform >= 1.14.0 (future use)
# ==========================================================================

# action "bcm_cmdevice_power" "provision" {
#   for_each = local.power_action_nodes
#
#   device_id           = bcm_cmdevice_device.nodes[each.key].uuid
#   power_action        = var.power_action
#   wait_for_completion = true
#   timeout             = var.power_action_timeout
# }
