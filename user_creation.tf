# Automated User Creation via Ansible
# Feature: BCM-based Kubernetes Deployment via Kubespray
#
# Automatically creates the Ansible service account on BCM nodes using an
# Ansible playbook executed via Terraform before Kubespray deployment.
#
# This replaces manual user creation and ensures the user exists before
# any SSH connectivity checks or Kubespray deployment.

# =============================================================================
# Ansible Inventory for Admin Access
# =============================================================================

locals {
  # Ansible inventory for user creation (connects as admin user)
  user_creation_inventory = {
    all = {
      hosts = {
        for hostname, ip in local.node_ips :
        hostname => {
          ansible_host = ip
          ansible_user = var.admin_ssh_user
          ansible_ssh_private_key_file = var.admin_ssh_private_key_path
          ansible_ssh_common_args = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o HostKeyAlgorithms=+ssh-rsa,ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa"
        }
      }
    }
  }
}

# =============================================================================
# Write Admin Inventory File
# =============================================================================

resource "local_file" "admin_inventory" {
  count = var.skip_user_creation ? 0 : 1

  content = yamlencode(local.user_creation_inventory)
  filename = "${path.module}/generated_admin_inventory.yml"
  file_permission = "0600"

  depends_on = [tls_private_key.ssh_key]
}

# =============================================================================
# Run Ansible Playbook to Create User
# =============================================================================

resource "terraform_data" "create_user" {
  count = var.skip_user_creation ? 0 : 1

  lifecycle {
    precondition {
      condition     = var.admin_ssh_private_key_path != null && var.admin_ssh_private_key_path != ""
      error_message = "The admin_ssh_private_key_path variable must be set when skip_user_creation=false. Set it to the path of your admin SSH private key (e.g., ~/.ssh/id_rsa) or set skip_user_creation=true if the user already exists."
    }
  }

  triggers_replace = [
    # Re-run if nodes change
    join(",", keys(local.node_ips)),
    # Re-run if user configuration changes
    var.node_username,
    var.node_user_uid,
    var.node_user_gid,
    # Re-run if SSH key changes
    tls_private_key.ssh_key.id
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "=========================================="
      echo "Creating Ansible Service Account"
      echo "=========================================="
      echo "Username: ${var.node_username}"
      echo "UID: ${var.node_user_uid}"
      echo "GID: ${var.node_user_gid}"
      echo "Target Nodes: ${join(", ", keys(local.node_ips))}"
      echo "Admin User: ${var.admin_ssh_user}"
      echo "=========================================="

      # Check if ansible is available
      if ! command -v ansible-playbook &> /dev/null; then
        echo "ERROR: ansible-playbook not found in PATH"
        echo "Please install Ansible: pip install ansible"
        exit 1
      fi

      # Display Ansible version
      ansible-playbook --version

      # Run the user creation playbook
      ansible-playbook \
        -i ${local_file.admin_inventory[0].filename} \
        ${path.module}/playbooks/create-user.yml \
        -e "target_username=${var.node_username}" \
        -e "target_uid=${var.node_user_uid}" \
        -e "target_gid=${var.node_user_gid}" \
        -e "target_home_dir=${var.node_user_home_dir != null ? var.node_user_home_dir : "/home/${var.node_username}"}" \
        -e "target_shell=${var.node_user_shell}" \
        -e "ssh_public_key=${tls_private_key.ssh_key.public_key_openssh}" \
        -v

      echo "=========================================="
      echo "✓ User creation completed successfully"
      echo "=========================================="
    EOT
  }

  depends_on = [
    tls_private_key.ssh_key,
    local_file.admin_inventory
  ]
}

# =============================================================================
# Output
# =============================================================================

output "user_creation_status" {
  description = "Status of automated user creation"
  value = var.skip_user_creation ? "Skipped (user pre-exists)" : "Automated via Ansible playbook"
}
