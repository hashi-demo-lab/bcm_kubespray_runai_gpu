# Kubespray Inventory Generation
# Feature: vSphere VM Provisioning with Kubernetes Deployment via Kubespray
# Spec: /workspace/specs/001-vsphere-k8s-kubespray/spec.md
# User Story 2 (P2): Kubernetes Cluster Deployment (FR-011, FR-012)
#
# Using private module: tfo-apj-demos/single-virtual-machine/vsphere v1.4.2

# =============================================================================
# Write Inventory to File (for reference and manual playbook execution)
# =============================================================================

resource "local_file" "kubespray_inventory" {
  content  = yamlencode(local.kubespray_inventory)
  filename = "${path.module}/inventory.yml"

  depends_on = [
    module.k8s_control_plane_01,
    module.k8s_worker_01,
    module.k8s_worker_02
  ]
}
