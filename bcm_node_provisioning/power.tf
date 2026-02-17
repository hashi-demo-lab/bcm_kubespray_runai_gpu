# BCM Node Provisioning Module - Power Actions
#
# IPMI power control via BCM API.
# Power actions are gated by var.enable_power_action for safety.
#
# NOTE: The Terraform "action" block requires Terraform >= 1.14.0.
# This file is intentionally empty until the remote host is upgraded.
# When Terraform 1.14+ is available, uncomment the block below.

# ==========================================================================
# POWER ACTIONS — trigger PXE boot via IPMI (requires Terraform 1.14+)
# ==========================================================================

# action "bcm_cmdevice_power" "provision" {
#   for_each = local.power_action_nodes
#
#   device_id           = bcm_cmdevice_device.nodes[each.key].uuid
#   power_action        = var.power_action
#   wait_for_completion = true
#   timeout             = var.power_action_timeout
# }
