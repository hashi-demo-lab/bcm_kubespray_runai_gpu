# Kubeconfig Extraction for Platform Configuration
# Feature: BCM-based Kubernetes Deployment via Kubespray
# Purpose: Export kubeconfig credentials for consumption by platform Terraform config

# =============================================================================
# Fetch Kubeconfig from Control Plane After Kubespray Deployment
# =============================================================================

# Get the first control plane node IP for kubeconfig extraction
locals {
  first_control_plane_ip = length(var.control_plane_nodes) > 0 ? (
    contains(keys(local.node_ips), var.control_plane_nodes[0]) ?
    local.node_ips[var.control_plane_nodes[0]] :
    null
  ) : null
}

data "external" "fetch_kubeconfig" {
  count = var.enable_kubespray_deployment && local.first_control_plane_ip != null ? 1 : 0

  program = ["bash", "${path.module}/scripts/fetch-kubeconfig.sh"]

  query = {
    control_plane_ip = local.first_control_plane_ip
    ssh_user         = var.ssh_user
    ssh_private_key  = tls_private_key.ssh_key.private_key_pem
  }

  depends_on = [
    terraform_data.run_kubespray
  ]
}
