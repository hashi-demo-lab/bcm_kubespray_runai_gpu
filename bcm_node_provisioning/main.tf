# BCM Node Provisioning Module - Main Resources
#
# Device resources for bare metal node provisioning.

# ==========================================================================
# AUTO-IMPORT — adopt existing BCM nodes into Terraform state
# ==========================================================================
# Queries BCM for all existing nodes, then generates import blocks for any
# node in var.nodes that already exists in BCM but not in Terraform state.
# This prevents addDevice from failing on duplicate hostnames and avoids
# overwriting existing node configurations (e.g., static IPs → DHCP).

data "bcm_cmdevice_nodes" "existing" {}

locals {
  # Map existing BCM nodes by hostname → UUID for import lookup
  existing_node_ids = {
    for node in try(data.bcm_cmdevice_nodes.existing.nodes, []) :
    node.hostname => node.id
  }
}

import {
  for_each = {
    for hostname, config in var.nodes :
    hostname => local.existing_node_ids[hostname]
    if contains(keys(local.existing_node_ids), hostname)
  }
  to = bcm_cmdevice_device.nodes[each.key]
  id = each.value
}

# ==========================================================================
# DEVICE RESOURCES — one per node in var.nodes
# ==========================================================================

resource "bcm_cmdevice_device" "nodes" {
  for_each = var.nodes

  hostname           = each.key
  mac                = each.value.mac
  category           = local.category_uuid_map[each.value.category]
  management_network = local.management_network_id
  power_control      = "ipmi0"
  notes              = "Managed by Terraform - bcm_node_provisioning module"

  # BMC interface registration — sent to the BCM head node API only.
  # This tells BCM where each node's IPMI interface is so BCM can manage
  # power control internally. Terraform NEVER contacts these IPs directly.
  # The 10.229.10.x (ipminet) addresses are out-of-band and unreachable from
  # Terraform; only the BCM head node communicates with them.
  dynamic "interfaces" {
    for_each = each.value.ipmi_ip != null ? [1] : []
    content {
      name    = "ipmi0"
      type    = "bmc"
      ip      = each.value.ipmi_ip
      network = local.oob_network_id
    }
  }

  # Primary physical interface — bootable for PXE, static IP required
  interfaces {
    name     = "BOOTIF"
    type     = "physical"
    mac      = each.value.mac
    network  = local.management_network_id
    ip       = each.value.management_ip
    dhcp     = false
    bootable = true
  }

  # Additional interfaces from variable
  dynamic "interfaces" {
    for_each = each.value.interfaces
    content {
      name     = interfaces.key
      type     = interfaces.value.type
      mac      = interfaces.value.mac
      network  = interfaces.value.network
      bootable = interfaces.value.bootable
      ip       = interfaces.value.ip
    }
  }

  # Role assignments (role names, not UUIDs)
  roles = length(each.value.roles) > 0 ? toset(each.value.roles) : null

  # Workaround: BCM provider has bugs that cause inconsistent results
  # on update (interface types, roles, bootable). Ignore all mutable
  # attributes to prevent any device updates via the provider.
  # Category and power changes are handled via cmsh local-exec instead.
  lifecycle {
    ignore_changes = all
  }
}
