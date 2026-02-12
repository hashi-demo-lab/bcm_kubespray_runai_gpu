# BCM Node Provisioning Module - Main Resources
#
# Device resources for bare metal node provisioning.

# ==========================================================================
# DEVICE RESOURCES — one per node in var.nodes
# ==========================================================================

resource "bcm_cmdevice_device" "nodes" {
  for_each = var.nodes

  hostname           = each.key
  mac                = each.value.mac
  category           = local.category_uuid_map[each.value.category]
  management_network = local.management_network_id
  power_control      = "ipmi"
  notes              = "Managed by Terraform - bcm_node_provisioning module"

  # BMC interface
  interfaces {
    name    = "ipmi"
    type    = "bmc"
    mac     = each.value.bmc_mac
    ip      = each.value.ipmi_ip
    network = local.oob_network_id
  }

  # Primary physical interface — bootable for PXE
  interfaces {
    name     = "eth0"
    type     = "physical"
    mac      = each.value.mac
    network  = local.management_network_id
    bootable = true
    ip       = each.value.management_ip
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
  roles = toset(each.value.roles)

  # Preserve device identity during re-provisioning (US2)
  lifecycle {
    ignore_changes = [
      notes,
    ]
  }
}
