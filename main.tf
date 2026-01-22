# BCM Node Discovery and Inventory Generation
# Feature: BCM-based Kubernetes Deployment via Kubespray
#
# This configuration queries BCM for physical nodes, filters by specified
# hostnames, and builds an Ansible inventory for Kubespray deployment.

# =============================================================================
# BCM Node Discovery
# =============================================================================

# Fetch all nodes from BCM
data "bcm_cmdevice_nodes" "all" {}

# =============================================================================
# Node Filtering and IP Extraction
# =============================================================================

locals {
  # Combine all target nodes into a single list
  all_target_nodes = distinct(concat(
    var.control_plane_nodes,
    var.worker_nodes,
    var.etcd_nodes
  ))

  # Filter BCM nodes to only include our target nodes
  bcm_nodes = {
    for node in data.bcm_cmdevice_nodes.all.nodes :
    node.hostname => node
    if contains(local.all_target_nodes, node.hostname)
  }

  # Extract primary IP from first interface with an IP address
  node_ips = {
    for hostname, node in local.bcm_nodes :
    hostname => coalesce(
      try(
        [
          for iface in node.interfaces : iface.ip
          if iface.ip != null && iface.ip != "" && can(regex("^10\\.184\\.162\\.", iface.ip))
        ][0],
        null
      ),
      try(
        [
          for iface in node.interfaces : iface.ip
          if iface.ip != null && iface.ip != "" && iface.ip != "0.0.0.0"
        ][0],
        null
      )
    )
  }

  # Separate nodes by role for Kubespray inventory
  control_plane_node_data = {
    for hostname in var.control_plane_nodes :
    hostname => local.bcm_nodes[hostname]
    if contains(keys(local.bcm_nodes), hostname)
  }

  worker_node_data = {
    for hostname in var.worker_nodes :
    hostname => local.bcm_nodes[hostname]
    if contains(keys(local.bcm_nodes), hostname)
  }

  # etcd nodes default to control plane nodes if not specified
  effective_etcd_nodes = length(var.etcd_nodes) > 0 ? var.etcd_nodes : var.control_plane_nodes

  etcd_node_data = {
    for hostname in local.effective_etcd_nodes :
    hostname => local.bcm_nodes[hostname]
    if contains(keys(local.bcm_nodes), hostname)
  }
}

# =============================================================================
# Outputs for Debugging and Verification
# =============================================================================

output "discovered_nodes" {
  description = "All nodes discovered from BCM"
  value = [
    for node in data.bcm_cmdevice_nodes.all.nodes :
    {
      hostname = node.hostname
      uuid     = node.uuid
      type     = node.child_type
    }
  ]
}

output "target_nodes" {
  description = "Filtered target nodes with their details"
  value = {
    for hostname, node in local.bcm_nodes :
    hostname => {
      uuid       = node.uuid
      type       = node.child_type
      mac        = node.mac
      ip         = local.node_ips[hostname]
      interfaces = length(node.interfaces)
      roles = [
        for role in node.roles :
        role.name if role.name != null
      ]
    }
  }
}

output "node_role_assignments" {
  description = "Node assignments by Kubernetes role"
  value = {
    control_plane = keys(local.control_plane_node_data)
    workers       = keys(local.worker_node_data)
    etcd          = keys(local.etcd_node_data)
  }
}
