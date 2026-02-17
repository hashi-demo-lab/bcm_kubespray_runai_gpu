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
  power_control      = "ipmi0"
  notes              = "Managed by Terraform - bcm_node_provisioning module"

  # BMC interface (only when ipmi_ip is provided)
  # Note: BMC MAC is not required by the BCM API for BMC interfaces
  dynamic "interfaces" {
    for_each = each.value.ipmi_ip != null ? [1] : []
    content {
      name    = "ipmi0"
      type    = "bmc"
      ip      = each.value.ipmi_ip
      network = local.oob_network_id
    }
  }

  # Primary physical interface — bootable for PXE
  interfaces {
    name     = "BOOTIF"
    type     = "physical"
    mac      = each.value.mac
    network  = local.management_network_id
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
  roles = length(each.value.roles) > 0 ? toset(each.value.roles) : null

  # Workaround: BCM provider has bugs that cause inconsistent results
  # on update (interface types, roles, bootable). Ignore all mutable
  # attributes to prevent any device updates via the provider.
  # Category and power changes are handled via cmsh local-exec instead.
  lifecycle {
    ignore_changes = all
  }
}
