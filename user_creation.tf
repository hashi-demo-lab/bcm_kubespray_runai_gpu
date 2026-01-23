# Automated User Creation via Ansible
# Feature: BCM-based Kubernetes Deployment via Kubespray
#
# Automatically detects if the user exists on BCM nodes and creates it if needed.
# This replaces manual user creation and ensures the user exists before
# any SSH connectivity checks or Kubespray deployment.

# =============================================================================
# Check if User Already Exists on Nodes
# =============================================================================

data "external" "check_user_exists" {
  # Only run check if we're not explicitly skipping user creation and admin key is provided
  count = !var.skip_user_creation && var.admin_ssh_private_key_path != null ? 1 : 0

  program = ["bash", "${path.module}/scripts/check-user-exists.sh"]

  query = {
    nodes           = join(",", [for hostname, ip in local.node_ips : ip])
    admin_user      = var.admin_ssh_user
    admin_key       = var.admin_ssh_private_key_path
    target_username = var.node_username
  }
}

# =============================================================================
# Determine if User Creation is Needed
# =============================================================================

locals {
  # Determine if we should actually create the user
  should_create_user = (
    # Don't create if explicitly skipped
    !var.skip_user_creation &&
    # Don't create if user already exists on all nodes
    (length(data.external.check_user_exists) == 0 ||
     try(data.external.check_user_exists[0].result.user_exists, "false") == "false")
  )

  # Check method from the script
  check_method = length(data.external.check_user_exists) > 0 ? try(data.external.check_user_exists[0].result.check_method, "not_checked") : "not_checked"

  # Check error message if any
  check_error = length(data.external.check_user_exists) > 0 ? try(data.external.check_user_exists[0].result.error, "none") : "none"

  # User status for output
  user_status = (
    var.skip_user_creation ? "Skipped (skip_user_creation=true)" :
    length(data.external.check_user_exists) == 0 ? "Skipped (no admin SSH key provided)" :
    local.check_method == "error" ? "Creating (check failed: ${local.check_error})" :
    local.check_method == "skipped" ? "Creating (SSH key not found, assuming user doesn't exist)" :
    try(data.external.check_user_exists[0].result.user_exists, "false") == "true" ? "Skipped (user already exists on all nodes)" :
    try(data.external.check_user_exists[0].result.user_exists, "false") == "partial" ? "ERROR: User exists on some but not all nodes" :
    "Creating (user not found on any node)"
  )
}

# =============================================================================
# Validation: Fail if User Exists on Some But Not All Nodes
# =============================================================================

resource "terraform_data" "validate_user_state" {
  count = !var.skip_user_creation && length(data.external.check_user_exists) > 0 ? 1 : 0

  lifecycle {
    precondition {
      condition     = try(data.external.check_user_exists[0].result.user_exists, "false") != "partial"
      error_message = "User '${var.node_username}' exists on some nodes but not all. Found on ${try(data.external.check_user_exists[0].result.nodes_with_user, "?")} of ${try(data.external.check_user_exists[0].result.checked_nodes, "?")} nodes. Please ensure the user either exists on ALL nodes or NONE, then run terraform apply again."
    }
  }
}

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
          ansible_host                  = ip
          ansible_user                  = var.admin_ssh_user
          ansible_ssh_private_key_file  = var.admin_ssh_private_key_path
          ansible_ssh_common_args       = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o HostKeyAlgorithms=+ssh-rsa,ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa"
        }
      }
    }
  }
}

# =============================================================================
# Write Admin Inventory File
# =============================================================================

resource "local_file" "admin_inventory" {
  count = local.should_create_user ? 1 : 0

  content         = yamlencode(local.user_creation_inventory)
  filename        = "${path.module}/generated_admin_inventory.yml"
  file_permission = "0600"

  depends_on = [tls_private_key.ssh_key]
}

# =============================================================================
# Run Ansible Playbook to Create User
# =============================================================================

resource "terraform_data" "create_user" {
  count = local.should_create_user ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.admin_ssh_private_key_path != null && var.admin_ssh_private_key_path != ""
      error_message = "The admin_ssh_private_key_path variable must be set to check/create the user. Set it to the path of your admin SSH private key (e.g., ~/.ssh/id_rsa)."
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

      # Ensure Ansible dependencies are installed (jinja2, etc.)
      echo "Checking Ansible dependencies..."
      pip3 install --user --quiet jinja2 PyYAML 2>/dev/null || \
        pip3 install --break-system-packages --quiet jinja2 PyYAML 2>/dev/null || \
        pip install --user --quiet jinja2 PyYAML 2>/dev/null || \
        echo "Warning: Could not install dependencies, Ansible may fail"

      # Use project ansible.cfg and disable vault password to avoid system config issues
      export ANSIBLE_CONFIG="${path.module}/ansible.cfg"
      export ANSIBLE_VAULT_PASSWORD_FILE=""
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
    local_file.admin_inventory,
    terraform_data.validate_user_state
  ]
}

# =============================================================================
# Output
# =============================================================================

output "user_creation_status" {
  description = "Status of automated user creation"
  value       = local.user_status
}

output "user_check_result" {
  description = "Result of user existence check"
  value = length(data.external.check_user_exists) > 0 ? {
    user_exists     = try(data.external.check_user_exists[0].result.user_exists, "not_checked")
    checked_nodes   = try(data.external.check_user_exists[0].result.checked_nodes, "0")
    nodes_with_user = try(data.external.check_user_exists[0].result.nodes_with_user, "0")
    check_method    = try(data.external.check_user_exists[0].result.check_method, "not_checked")
    error           = try(data.external.check_user_exists[0].result.error, "none")
  } : {
    user_exists     = "not_checked"
    checked_nodes   = "0"
    nodes_with_user = "0"
    check_method    = "not_checked"
    error           = "none"
  }
}
