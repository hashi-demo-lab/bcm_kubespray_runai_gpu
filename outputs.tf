# Output Value Declarations
# Feature: vSphere VM Provisioning with Kubernetes Deployment via Kubespray
# Spec: /workspace/specs/001-vsphere-k8s-kubespray/spec.md
# Data Model: /workspace/specs/001-vsphere-k8s-kubespray/data-model.md
#
# Using private module: tfo-apj-demos/single-virtual-machine/vsphere v1.4.2

# =============================================================================
# VM Infrastructure Outputs (FR-015)
# =============================================================================

output "control_plane_hostname" {
  description = "Hostname of Kubernetes control plane node"
  value       = module.k8s_control_plane_01.virtual_machine_name
}

output "control_plane_ip" {
  description = "IP address of Kubernetes control plane node for API access"
  value       = module.k8s_control_plane_01.ip_address
}

output "control_plane_vm_id" {
  description = "vSphere VM ID of control plane node"
  value       = module.k8s_control_plane_01.virtual_machine_id
}

output "worker_hostnames" {
  description = "Hostnames of Kubernetes worker nodes"
  value = [
    module.k8s_worker_01.virtual_machine_name,
    module.k8s_worker_02.virtual_machine_name
  ]
}

output "worker_ips" {
  description = "IP addresses of Kubernetes worker nodes"
  value = [
    module.k8s_worker_01.ip_address,
    module.k8s_worker_02.ip_address
  ]
}

output "worker_vm_ids" {
  description = "vSphere VM IDs of worker nodes"
  value = [
    module.k8s_worker_01.virtual_machine_id,
    module.k8s_worker_02.virtual_machine_id
  ]
}

output "all_node_ips" {
  description = "All Kubernetes node IP addresses for monitoring integration"
  value       = local.vm_ip_addresses
}

# =============================================================================
# Kubernetes Cluster Outputs (FR-015)
# =============================================================================

output "cluster_name" {
  description = "Kubernetes cluster name for kubectl configuration"
  value       = var.cluster_name
}

output "kubernetes_version" {
  description = "Deployed Kubernetes version"
  value       = var.kubernetes_version
}

output "cni_plugin" {
  description = "Deployed CNI plugin for pod networking"
  value       = var.cni_plugin
}

output "kubernetes_api_endpoint" {
  description = "Kubernetes API server endpoint (https://<control_plane_ip>:6443)"
  value       = "https://${module.k8s_control_plane_01.ip_address}:6443"
}

# =============================================================================
# Ansible Inventory Outputs (FR-016)
# =============================================================================

output "kubespray_inventory" {
  description = "Generated Kubespray inventory in YAML format"
  value       = yamlencode(local.kubespray_inventory)
  sensitive   = false
}

output "inventory_file_path" {
  description = "Path to generated inventory.yml file"
  value       = local_file.kubespray_inventory.filename
}

# =============================================================================
# SSH Access Information (FR-013)
# =============================================================================

output "ssh_user" {
  description = "SSH username for VM access"
  value       = var.ssh_user
}

output "ssh_connection_strings" {
  description = "SSH connection commands for each node"
  value = {
    control_plane = "ssh ${var.ssh_user}@${module.k8s_control_plane_01.ip_address}"
    worker_01     = "ssh ${var.ssh_user}@${module.k8s_worker_01.ip_address}"
    worker_02     = "ssh ${var.ssh_user}@${module.k8s_worker_02.ip_address}"
  }
}

# =============================================================================
# Kubeconfig Outputs for Platform Configuration (Remote State)
# These outputs are consumed by the platform Terraform configuration
# =============================================================================

output "kubeconfig_ca_certificate" {
  description = "Base64-encoded Kubernetes cluster CA certificate"
  value       = var.enable_kubespray_deployment ? data.external.fetch_kubeconfig[0].result.kubeconfig_ca_certificate : ""
  sensitive   = true
}

output "kubeconfig_client_certificate" {
  description = "Base64-encoded Kubernetes client certificate"
  value       = var.enable_kubespray_deployment ? data.external.fetch_kubeconfig[0].result.kubeconfig_client_certificate : ""
  sensitive   = true
}

output "kubeconfig_client_key" {
  description = "Base64-encoded Kubernetes client private key"
  value       = var.enable_kubespray_deployment ? data.external.fetch_kubeconfig[0].result.kubeconfig_client_key : ""
  sensitive   = true
}
