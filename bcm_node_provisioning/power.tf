# BCM Node Provisioning Module - Power Actions
#
# IPMI power control via BCM API (Terraform 1.14+ Actions feature).
# Power actions are gated by var.enable_power_action for safety.

# ==========================================================================
# POWER ACTIONS — trigger PXE boot via IPMI
# ==========================================================================

action "bcm_cmdevice_power" "provision" {
  for_each = local.power_action_nodes

  device_id           = bcm_cmdevice_device.nodes[each.key].uuid
  power_action        = var.power_action
  wait_for_completion = true
  timeout             = var.power_action_timeout
}
