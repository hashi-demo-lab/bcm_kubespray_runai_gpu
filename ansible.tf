# Ansible Integration for Kubespray Deployment
# Feature: BCM-based Kubernetes Deployment via Kubespray
#
# This configuration deploys Kubernetes using Kubespray to BCM-discovered nodes.

# =============================================================================
# Wait for Nodes to be SSH Accessible
# =============================================================================

resource "terraform_data" "wait_for_nodes" {
  count = var.enable_ansible ? length(local.vm_ip_addresses) : 0

  triggers_replace = [
    local.vm_ip_addresses[count.index]
  ]

  provisioner "remote-exec" {
    inline = ["echo 'Node is ready for Ansible provisioning'"]

    connection {
      type        = "ssh"
      user        = var.ssh_user
      private_key = tls_private_key.ssh_key.private_key_pem
      host        = local.vm_ip_addresses[count.index]
      timeout     = "5m"
    }
  }
}

# =============================================================================
# Clone and Setup Kubespray
# =============================================================================

resource "terraform_data" "clone_kubespray" {
  count = var.enable_kubespray_deployment ? 1 : 0

  triggers_replace = [
    var.kubespray_version,
    var.kubernetes_version,
    # Force re-run when script logic changes
    "v11-use-builtin-venv"
  ]

  # Clone Kubespray repository on the agent
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "=== Setting up Python 3.9 virtual environment ==="

      # Verify Python 3.9 is available
      python3.9 --version || { echo "ERROR: Python 3.9 not found"; exit 1; }

      # Use built-in venv module instead of virtualenv (avoids extra install and memory usage)
      echo "Removing old virtualenv if exists..."
      rm -rf /tmp/kubespray-venv
      
      echo "Creating virtualenv with python3.9 -m venv..."
      python3.9 -m venv /tmp/kubespray-venv
      
      echo "Activating virtualenv..."
      . /tmp/kubespray-venv/bin/activate

      # Upgrade pip with constraints to reduce memory
      echo "Upgrading pip..."
      pip install --upgrade pip --no-cache-dir

      echo "=== Cloning Kubespray ${var.kubespray_version} ==="

      rm -rf /tmp/kubespray
      git clone --depth 1 --branch ${var.kubespray_version} https://github.com/kubernetes-sigs/kubespray.git /tmp/kubespray

      # Check Python version (should be 3.9)
      PYTHON_VERSION=$(python3.9 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
      echo "Python version: $PYTHON_VERSION"

      # Install Kubespray requirements into virtualenv (no cache to save memory)
      echo "Installing Kubespray requirements..."
      pip install --no-cache-dir -r /tmp/kubespray/requirements.txt

      # Verify ansible version in virtualenv
      echo "=== Ansible version in virtualenv ==="
      /tmp/kubespray-venv/bin/ansible --version

      # Prepare inventory directory
      mkdir -p /tmp/kubespray/inventory/mycluster
      cp -rfp /tmp/kubespray/inventory/sample/group_vars /tmp/kubespray/inventory/mycluster/

      echo "=== Kubespray clone complete ==="
    EOT
  }
}

# =============================================================================
# Run Kubespray Deployment
# =============================================================================

resource "terraform_data" "run_kubespray" {
  count = var.enable_kubespray_deployment ? 1 : 0

  triggers_replace = [
    # Trigger on any node IP change
    join(",", local.vm_ip_addresses),
    var.kubernetes_version,
    var.cni_plugin,
    var.cluster_name
  ]

  # Write inventory and SSH key, then run Kubespray
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "=== Preparing Kubespray deployment ==="

      # Write SSH private key
      cat > /tmp/kubespray_ssh_key << 'SSHKEY'
${tls_private_key.ssh_key.private_key_pem}
SSHKEY
      chmod 600 /tmp/kubespray_ssh_key

      # Write inventory file
      cat > /tmp/kubespray/inventory/mycluster/hosts.yml << 'INVENTORY'
${yamlencode(local.kubespray_inventory)}
INVENTORY

      # Update inventory to use our SSH key path
      sed -i 's|~/.ssh/id_rsa|/tmp/kubespray_ssh_key|g' /tmp/kubespray/inventory/mycluster/hosts.yml

      echo "=== Inventory file ==="
      cat /tmp/kubespray/inventory/mycluster/hosts.yml

      # Configure SSH options
      export ANSIBLE_HOST_KEY_CHECKING=False
      export ANSIBLE_SSH_ARGS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

      echo "=== Starting Kubespray cluster deployment ==="

      # Use ansible from virtualenv to avoid system ansible 2.12 conflicts
      echo "=== Using virtualenv ansible ==="
      /tmp/kubespray-venv/bin/ansible --version

      cd /tmp/kubespray

      /tmp/kubespray-venv/bin/ansible-playbook -i inventory/mycluster/hosts.yml cluster.yml \
        -b -v \
        --private-key=/tmp/kubespray_ssh_key \
        -e "kube_version=${var.kubernetes_version}" \
        -e "kube_network_plugin=${var.cni_plugin}" \
        -e "cluster_name=${var.cluster_name}" \
        -e "ansible_user=${var.ssh_user}" \
        -e "ansible_ssh_private_key_file=/tmp/kubespray_ssh_key"

      echo "=== Kubespray deployment completed ==="

      # Cleanup sensitive files
      rm -f /tmp/kubespray_ssh_key
    EOT
  }

  depends_on = [
    terraform_data.clone_kubespray,
    terraform_data.wait_for_nodes,
    local_file.kubespray_inventory
  ]
}
