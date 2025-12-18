# Kubespray Inventory Generation
# Feature: BCM-based Kubernetes Deployment via Kubespray
#
# Generates Ansible inventory files from BCM-discovered nodes.

# =============================================================================
# Write Inventory to File (for reference and manual playbook execution)
# =============================================================================

resource "local_file" "kubespray_inventory" {
  content  = yamlencode(local.kubespray_inventory)
  filename = "${path.module}/inventory.yml"

  file_permission = "0644"
}
