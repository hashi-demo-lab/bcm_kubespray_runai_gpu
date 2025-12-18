# Kubeconfig Extraction for Platform Configuration
# Feature: vSphere VM Provisioning with Kubernetes Deployment via Kubespray
# Spec: /workspace/specs/001-vsphere-k8s-kubespray/spec.md
# Purpose: Export kubeconfig credentials for consumption by platform Terraform config

# =============================================================================
# Fetch Kubeconfig from Control Plane After Kubespray Deployment
# =============================================================================

data "external" "fetch_kubeconfig" {
  count = var.enable_kubespray_deployment ? 1 : 0

  program = ["bash", "${path.module}/scripts/fetch-kubeconfig.sh"]

  query = {
    control_plane_ip = module.k8s_control_plane_01.ip_address
    ssh_user         = var.ssh_user
    ssh_private_key  = tls_private_key.ssh_key.private_key_pem
  }

  depends_on = [
    terraform_data.run_kubespray
  ]
}
