# Local Computed Values
# Feature: BCM-based Kubernetes Deployment via Kubespray
#
# This configuration builds the Kubespray inventory structure dynamically
# from BCM-discovered nodes.

locals {
  # =============================================================================
  # SSH Key Configuration
  # =============================================================================
  # Use generated key if user doesn't provide their own
  ssh_private_key_content = var.ssh_private_key != null ? var.ssh_private_key : tls_private_key.ssh_key.private_key_pem
  ssh_private_key_path    = var.ssh_private_key_path != null ? var.ssh_private_key_path : local_sensitive_file.ssh_private_key.filename

  # =============================================================================
  # Kubespray Inventory Structure
  # =============================================================================
  # Builds the inventory structure required by Kubespray for cluster deployment.
  # Nodes are dynamically assigned to groups based on var.control_plane_nodes,
  # var.worker_nodes, and var.etcd_nodes configuration.

  kubespray_inventory = {
    all = {
      # All hosts with their connection details and BCM metadata
      hosts = merge(
        # Control plane nodes
        {
          for hostname in var.control_plane_nodes :
          hostname => {
            ansible_host = local.node_ips[hostname]
            ip           = local.node_ips[hostname]
            access_ip    = local.node_ips[hostname]
            # BCM metadata for reference
            bcm_uuid = try(local.bcm_nodes[hostname].uuid, null)
            bcm_mac  = try(local.bcm_nodes[hostname].mac, null)
            bcm_type = try(local.bcm_nodes[hostname].child_type, null)
          }
          if contains(keys(local.bcm_nodes), hostname)
        },
        # Worker nodes
        {
          for hostname in var.worker_nodes :
          hostname => {
            ansible_host = local.node_ips[hostname]
            ip           = local.node_ips[hostname]
            access_ip    = local.node_ips[hostname]
            # BCM metadata for reference
            bcm_uuid = try(local.bcm_nodes[hostname].uuid, null)
            bcm_mac  = try(local.bcm_nodes[hostname].mac, null)
            bcm_type = try(local.bcm_nodes[hostname].child_type, null)
          }
          if contains(keys(local.bcm_nodes), hostname)
        }
      )

      # Kubespray group structure
      children = {
        # Control plane nodes (Kubernetes masters)
        kube_control_plane = {
          hosts = {
            for hostname in var.control_plane_nodes :
            hostname => {}
            if contains(keys(local.bcm_nodes), hostname)
          }
        }

        # Worker nodes
        kube_node = {
          hosts = {
            for hostname in var.worker_nodes :
            hostname => {}
            if contains(keys(local.bcm_nodes), hostname)
          }
        }

        # etcd nodes (defaults to control plane if not specified)
        etcd = {
          hosts = {
            for hostname in local.effective_etcd_nodes :
            hostname => {}
            if contains(keys(local.bcm_nodes), hostname)
          }
        }

        # Kubernetes cluster group (combines control plane and workers)
        k8s_cluster = {
          children = {
            kube_control_plane = {}
            kube_node          = {}
          }
        }

        # Calico route reflectors (empty by default)
        calico_rr = {
          hosts = {}
        }
      }

      # Global Ansible variables
      vars = {
        ansible_user                 = var.ssh_user
        ansible_ssh_private_key_file = local.ssh_private_key_path
        ansible_become               = true
        ansible_become_method        = "sudo"
      }
    }
  }

  # =============================================================================
  # VM IP Addresses (for SSH validation)
  # =============================================================================
  # Use hostnames instead of BCM IPs since hostname resolution (10.184.x.x)
  # differs from BCM interface IPs (10.229.x.x) and SSH keys are set up
  # on the hostname-resolved network.

  vm_ip_addresses = [
    for hostname in local.all_target_nodes :
    hostname # Use hostname instead of IP - SSH resolves via /etc/hosts or DNS
    if contains(keys(local.bcm_nodes), hostname)
  ]
}
