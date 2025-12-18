# Output Value Declarations
# Feature: BCM-based Kubernetes Deployment via Kubespray
#
# This configuration outputs cluster information for BCM-discovered nodes.

# =============================================================================
# Control Plane Node Outputs
# =============================================================================

output "control_plane_nodes" {
  description = "Control plane node details"
  value = {
    for hostname in var.control_plane_nodes :
    hostname => {
      ip       = local.node_ips[hostname]
      bcm_uuid = try(local.bcm_nodes[hostname].uuid, null)
      bcm_type = try(local.bcm_nodes[hostname].child_type, null)
    }
    if contains(keys(local.bcm_nodes), hostname)
  }
}

output "control_plane_ips" {
  description = "IP addresses of Kubernetes control plane nodes"
  value = [
    for hostname in var.control_plane_nodes :
    local.node_ips[hostname]
    if contains(keys(local.bcm_nodes), hostname)
  ]
}

# =============================================================================
# Worker Node Outputs
# =============================================================================

output "worker_nodes" {
  description = "Worker node details"
  value = {
    for hostname in var.worker_nodes :
    hostname => {
      ip       = local.node_ips[hostname]
      bcm_uuid = try(local.bcm_nodes[hostname].uuid, null)
      bcm_type = try(local.bcm_nodes[hostname].child_type, null)
    }
    if contains(keys(local.bcm_nodes), hostname)
  }
}

output "worker_ips" {
  description = "IP addresses of Kubernetes worker nodes"
  value = [
    for hostname in var.worker_nodes :
    local.node_ips[hostname]
    if contains(keys(local.bcm_nodes), hostname)
  ]
}

# =============================================================================
# All Node Outputs
# =============================================================================

output "all_node_ips" {
  description = "All Kubernetes node IP addresses"
  value       = local.vm_ip_addresses
}

# =============================================================================
# Kubernetes Cluster Outputs
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
  value = length(var.control_plane_nodes) > 0 ? (
    contains(keys(local.node_ips), var.control_plane_nodes[0]) ?
    "https://${local.node_ips[var.control_plane_nodes[0]]}:6443" :
    null
  ) : null
}

# =============================================================================
# Ansible Inventory Outputs
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
# SSH Access Information
# =============================================================================

output "ssh_user" {
  description = "SSH username for node access"
  value       = var.ssh_user
}

output "ssh_connection_strings" {
  description = "SSH connection commands for each node"
  value = {
    for hostname, node in local.bcm_nodes :
    hostname => "ssh ${var.ssh_user}@${local.node_ips[hostname]}"
  }
}

# =============================================================================
# Kubeconfig Outputs for Platform Configuration
# These outputs are consumed by the platform Terraform configuration
# =============================================================================

output "kubeconfig_ca_certificate" {
  description = "Base64-encoded Kubernetes cluster CA certificate"
  value       = var.enable_kubespray_deployment ? try(data.external.fetch_kubeconfig[0].result.kubeconfig_ca_certificate, "") : ""
  sensitive   = true
}

output "kubeconfig_client_certificate" {
  description = "Base64-encoded Kubernetes client certificate"
  value       = var.enable_kubespray_deployment ? try(data.external.fetch_kubeconfig[0].result.kubeconfig_client_certificate, "") : ""
  sensitive   = true
}

output "kubeconfig_client_key" {
  description = "Base64-encoded Kubernetes client private key"
  value       = var.enable_kubespray_deployment ? try(data.external.fetch_kubeconfig[0].result.kubeconfig_client_key, "") : ""
  sensitive   = true
}
