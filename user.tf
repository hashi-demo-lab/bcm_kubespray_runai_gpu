# User Management with SSH Key Configuration
# Feature: BCM-based Kubernetes Deployment via Kubespray
#
# Creates user accounts on BCM-managed nodes with supplied SSH public keys
# for passwordless authentication.

# =============================================================================
# Local Values for SSH Key Configuration
# =============================================================================

locals {
  # Combine generated SSH key with any additional user-supplied keys
  # The generated key from tls_private_key is always included for Ansible access
  all_ssh_public_keys_string = join("\n", concat(
    [tls_private_key.ssh_key.public_key_openssh],
    var.node_user_ssh_public_keys
  ))
}

# =============================================================================
# BCM User Resource with SSH Keys
# =============================================================================

resource "bcm_cmuser_user" "node_user" {
  username       = var.node_username
  password       = var.node_password
  full_name      = var.node_user_full_name
  home_directory = var.node_user_home_dir != null ? var.node_user_home_dir : "/home/${var.node_username}"
  shell          = var.node_user_shell
  notes          = "Ansible service account for Kubespray deployment"

  # Optional UID/GID
  uid = var.node_user_uid
  gid = var.node_user_gid

  # SSH public keys for passwordless authentication
  # Includes the generated key plus any additional user-supplied keys
  authorized_ssh_keys = local.all_ssh_public_keys_string

  # Ensure SSH key is generated before user creation
  depends_on = [tls_private_key.ssh_key]

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "created_users" {
  description = "User created on BCM with SSH key configuration"
  value = {
    username       = bcm_cmuser_user.node_user.username
    home_directory = bcm_cmuser_user.node_user.home_directory
    ssh_keys_count = length(compact(split("\n", local.all_ssh_public_keys_string)))
  }
}

output "user_ssh_public_key" {
  description = "The generated SSH public key configured for node users"
  value       = tls_private_key.ssh_key.public_key_openssh
}
