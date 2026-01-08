terraform {
  required_providers {
    bcm = {
      source  = "hashi-demo-lab/bcm"
      version = "~> 0.1.3"
    }
  }
  required_version = ">= 1.0"
}

# Query all nodes - hostname_pattern does substring matching, not regex
# So we'll filter in Terraform using the actual hostnames
data "bcm_cmdevice_nodes" "all" {}

# Filter master nodes (cpu-03, cpu-05, cpu-06)
locals {
  master_hostnames = ["cpu-03", "cpu-05", "cpu-06"]
  worker_hostnames = ["dgx-05", "dgx-06"]
  etcd_hostnames   = ["cpu-03", "cpu-05", "cpu-06"]

  # Filter nodes by hostname
  master_nodes = [
    for node in data.bcm_cmdevice_nodes.all.nodes :
    node if contains(local.master_hostnames, node.hostname)
  ]

  worker_nodes = [
    for node in data.bcm_cmdevice_nodes.all.nodes :
    node if contains(local.worker_hostnames, node.hostname)
  ]

  etcd_nodes = [
    for node in data.bcm_cmdevice_nodes.all.nodes :
    node if contains(local.etcd_hostnames, node.hostname)
  ]
}

# Query available networks
data "bcm_cmnet_networks" "all" {}

output "networks" {
  value = data.bcm_cmnet_networks.all.networks
}

# Debug outputs - show all discovered nodes
output "all_nodes" {
  description = "All nodes discovered from BCM"
  value = {
    count     = length(data.bcm_cmdevice_nodes.all.nodes)
    hostnames = [for node in data.bcm_cmdevice_nodes.all.nodes : node.hostname]
  }
}

output "etcd_nodes" {
  description = "Filtered etcd nodes"
  value = {
    count     = length(local.etcd_nodes)
    hostnames = [for node in local.etcd_nodes : node.hostname]
    uuids     = [for node in local.etcd_nodes : node.uuid]
  }
}

output "worker_nodes" {
  description = "Filtered worker nodes"
  value = {
    count     = length(local.worker_nodes)
    hostnames = [for node in local.worker_nodes : node.hostname]
    uuids     = [for node in local.worker_nodes : node.uuid]
  }
}

output "master_nodes" {
  description = "Filtered master nodes"
  value = {
    count     = length(local.master_nodes)
    hostnames = [for node in local.master_nodes : node.hostname]
    uuids     = [for node in local.master_nodes : node.uuid]
  }
}

# # Create the Kubernetes cluster based on cm-kubernetes-setup.conf
# resource "bcm_cmkube_cluster" "terraform" {
#   name = var.cluster_name

#   # Master nodes - require exactly 3 nodes (cpu-03, cpu-05, cpu-06)
#   master_nodes = length(data.bcm_cmdevice_nodes.masters.nodes) >= 3 ? [
#     for node in data.bcm_cmdevice_nodes.masters.nodes : node.id
#   ] : []

#   # Worker nodes - require exactly 2 nodes (dgx-05, dgx-06)
#   worker_nodes = length(data.bcm_cmdevice_nodes.workers.nodes) >= 2 ? [
#     for node in data.bcm_cmdevice_nodes.workers.nodes : node.id
#   ] : []

#   # Dedicated etcd nodes for HA (recommended for production)
#   # Using same nodes as masters (cpu-03, cpu-05, cpu-06)
#   etcd_nodes = length(data.bcm_cmdevice_nodes.etcd.nodes) >= 3 ? [
#     for node in data.bcm_cmdevice_nodes.etcd.nodes : node.id
#   ] : []

#   # Kubernetes version from config: 1.32
#   version = var.kubernetes_version

#   # CNI plugin: calico (from network_plugin setting)
#   cni_plugin = var.cni_plugin

#   # Management network - use first available network if exists
#   management_network = length(data.bcm_cmnet_networks.all.networks) > 0 ? data.bcm_cmnet_networks.all.networks[0].id : null

#   # Force flag - set based on variable
#   force = var.force_bypass_validation

# }
