# User Management with SSH Key Configuration
# Feature: BCM-based Kubernetes Deployment via Kubespray
#
# Creates user accounts on BCM-managed nodes with supplied SSH public keys
# for passwordless authentication.

# =============================================================================
# BCM User Resource with SSH Keys
# =============================================================================

resource "bcm_cmdevice_user" "node_user" {
  for_each = local.bcm_nodes

  # Target node identification
  node_id  = each.value.uuid
  hostname = each.key

  # User account configuration
  username    = var.node_username
  password    = var.node_password
  uid         = var.node_user_uid
  gid         = var.node_user_gid
  home_dir    = var.node_user_home_dir != null ? var.node_user_home_dir : "/home/${var.node_username}"
  shell       = var.node_user_shell
  sudo_access = var.node_user_sudo_access

  # SSH public keys for passwordless authentication
  ssh_authorized_keys = var.node_user_ssh_public_keys

  # Ensure user is created before Ansible attempts to connect
  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "created_users" {
  description = "Users created on BCM nodes with SSH key configuration"
  value = {
    for hostname, user in bcm_cmdevice_user.node_user :
    hostname => {
      username       = user.username
      home_dir       = user.home_dir
      sudo_access    = user.sudo_access
      ssh_keys_count = length(var.node_user_ssh_public_keys)
    }
  }
}
