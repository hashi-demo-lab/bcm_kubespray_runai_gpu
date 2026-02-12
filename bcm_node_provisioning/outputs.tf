# BCM Node Provisioning Module - Outputs

output "device_ids" {
  description = "Map of hostname to BCM device UUID"
  value = {
    for hostname, device in bcm_cmdevice_device.nodes :
    hostname => device.uuid
  }
}

output "device_details" {
  description = "Map of hostname to device details (UUID, category, power control)"
  value = {
    for hostname, device in bcm_cmdevice_device.nodes :
    hostname => {
      uuid          = device.uuid
      hostname      = device.hostname
      mac           = device.mac
      power_control = device.power_control
      category      = device.category
    }
  }
}

output "software_image_uuid" {
  description = "UUID of the software image used for provisioning"
  value       = local.software_image_uuid
}

output "management_network_id" {
  description = "ID of the management network used for PXE boot"
  value       = local.management_network_id
}

output "power_action_enabled" {
  description = "Whether power actions were executed in this apply"
  value       = var.enable_power_action
}

output "node_count" {
  description = "Total number of nodes managed by this module"
  value       = length(var.nodes)
}

output "node_status" {
  description = "Per-node provisioning status: found, state, IP, success flag"
  value       = local.node_status
}

output "node_bmc_ips" {
  description = "Map of hostname to BMC/IPMI IP address for operational reference"
  value = {
    for hostname, config in var.nodes :
    hostname => config.ipmi_ip
  }
}

output "provisioning_summary" {
  description = "Summary counts: total, successful, failed, not_found"
  value = {
    total     = length(var.nodes)
    success   = length([for h, s in local.node_status : h if s.success])
    failed    = length([for h, s in local.node_status : h if s.found && !s.success])
    not_found = length([for h, s in local.node_status : h if !s.found])
  }
}
