terraform {
  required_providers {
    bcm = {
      source  = "hashi-demo-lab/bcm"
      version = "~> 0.1.3"
    }
  }
  required_version = ">= 1.0"
}

# Query master nodes (cpu nodes for control plane)
data "bcm_cmdevice_nodes" "masters" {
  filter {
    hostname_pattern = "cpu-0[356]" # cpu-03, cpu-05, cpu-06
  }
}

# Query worker nodes (dgx nodes)
data "bcm_cmdevice_nodes" "workers" {
  filter {
    hostname_pattern = "dgx-0[56]" # dgx-05, dgx-06
  }
}

# Query etcd nodes (same as masters in this config)
data "bcm_cmdevice_nodes" "etcd" {
  filter {
    hostname_pattern = "cpu-0[356]" # cpu-03, cpu-05, cpu-06
  }
}

# Query available networks
data "bcm_cmnet_networks" "all" {}

# Create the Kubernetes cluster based on cm-kubernetes-setup.conf
resource "bcm_cmkube_cluster" "terraform" {
  name = var.cluster_name

  # Master nodes - require exactly 3 nodes (cpu-03, cpu-05, cpu-06)
  master_nodes = length(data.bcm_cmdevice_nodes.masters.nodes) >= 3 ? [
    for node in data.bcm_cmdevice_nodes.masters.nodes : node.id
  ] : []

  # Worker nodes - require exactly 2 nodes (dgx-05, dgx-06)
  worker_nodes = length(data.bcm_cmdevice_nodes.workers.nodes) >= 2 ? [
    for node in data.bcm_cmdevice_nodes.workers.nodes : node.id
  ] : []

  # Dedicated etcd nodes for HA (recommended for production)
  # Using same nodes as masters (cpu-03, cpu-05, cpu-06)
  etcd_nodes = length(data.bcm_cmdevice_nodes.etcd.nodes) >= 3 ? [
    for node in data.bcm_cmdevice_nodes.etcd.nodes : node.id
  ] : []

  # Kubernetes version from config: 1.32
  version = var.kubernetes_version

  # CNI plugin: calico (from network_plugin setting)
  cni_plugin = var.cni_plugin

  # Management network - use first available network if exists
  management_network = length(data.bcm_cmnet_networks.all.networks) > 0 ? data.bcm_cmnet_networks.all.networks[0].id : null

  # Force flag - set based on variable
  force = var.force_bypass_validation

}
