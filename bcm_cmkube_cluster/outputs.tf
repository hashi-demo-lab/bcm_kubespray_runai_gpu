# Cluster Outputs
# Provides essential cluster information for integration with other resources

output "cluster_id" {
  description = "Cluster identifier (UUID)"
  value       = bcm_cmkube_cluster.terraform.id
}

output "cluster_uuid" {
  description = "BCM-assigned cluster UUID"
  value       = bcm_cmkube_cluster.terraform.uuid
}

output "cluster_name" {
  description = "Cluster name"
  value       = bcm_cmkube_cluster.terraform.name
}

output "cluster_version" {
  description = "Kubernetes version"
  value       = bcm_cmkube_cluster.terraform.version
}

output "cluster_creation_time" {
  description = "Cluster creation timestamp (Unix epoch)"
  value       = bcm_cmkube_cluster.terraform.creation_time
}

output "cluster_revision_id" {
  description = "BCM revision ID for optimistic locking"
  value       = bcm_cmkube_cluster.terraform.revision_id
}

output "master_node_count" {
  description = "Number of master nodes in the cluster"
  value       = length(bcm_cmkube_cluster.terraform.master_nodes)
}

output "worker_node_count" {
  description = "Number of worker nodes in the cluster"
  value       = length(bcm_cmkube_cluster.terraform.worker_nodes)
}

output "etcd_node_count" {
  description = "Number of etcd nodes in the cluster"
  value       = length(bcm_cmkube_cluster.terraform.etcd_nodes)
}

output "cni_plugin" {
  description = "CNI plugin used for pod networking"
  value       = bcm_cmkube_cluster.terraform.cni_plugin
}

output "management_network" {
  description = "Management network UUID"
  value       = bcm_cmkube_cluster.terraform.management_network
}

# Data source outputs for validation
output "master_nodes" {
  description = "Discovered master nodes from BCM"
  value = {
    count     = length(local.master_nodes)
    hostnames = [for node in local.master_nodes : node.hostname]
    uuids     = [for node in local.master_nodes : node.uuid]
  }
}

output "worker_nodes" {
  description = "Discovered worker nodes from BCM"
  value = {
    count     = length(local.worker_nodes)
    hostnames = [for node in local.worker_nodes : node.hostname]
    uuids     = [for node in local.worker_nodes : node.uuid]
  }
}

output "etcd_nodes" {
  description = "Discovered etcd nodes from BCM"
  value = {
    count     = length(local.etcd_nodes)
    hostnames = [for node in local.etcd_nodes : node.hostname]
    uuids     = [for node in local.etcd_nodes : node.uuid]
  }
}

# output "cluster_import_command" {
#   description = "Command to import this cluster into Terraform state"
#   value       = "terraform import bcm_cmkube_cluster.terraform ${bcm_cmkube_cluster.terraform.uuid}"
# }
