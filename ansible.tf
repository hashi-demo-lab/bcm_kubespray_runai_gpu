# Ansible Integration for Kubespray Deployment
# Feature: vSphere VM Provisioning with Kubernetes Deployment via Kubespray
# Spec: /workspace/specs/001-vsphere-k8s-kubespray/spec.md
# User Story 2 (P2): Kubernetes Cluster Deployment (FR-011, FR-013, FR-014)
#
# Using private module: tfo-apj-demos/single-virtual-machine/vsphere v1.4.2

# =============================================================================
# Wait for VMs to be SSH Accessible (FR-013)
# =============================================================================

resource "terraform_data" "wait_for_vms" {
  count = var.enable_ansible ? 3 : 0

  triggers_replace = [
    local.vm_ip_addresses[count.index],
    tls_private_key.ssh_key.public_key_openssh
  ]

  provisioner "remote-exec" {
    inline = ["echo 'VM is ready for Ansible provisioning'"]

    connection {
      type        = "ssh"
      user        = var.ssh_user
      private_key = tls_private_key.ssh_key.private_key_pem
      host        = local.vm_ip_addresses[count.index]
      timeout     = "5m"
    }
  }

  depends_on = [
    module.k8s_control_plane_01,
    module.k8s_worker_01,
    module.k8s_worker_02,
    tls_private_key.ssh_key
  ]
}

# =============================================================================
# Install Ansible on HCP Terraform Agent and Execute Kubespray (FR-011, FR-014)
# This downloads and installs Ansible on the agent, then runs the playbook
# against the provisioned VMs.
# =============================================================================

# resource "terraform_data" "install_ansible_on_agent" {
#   count = var.enable_kubespray_deployment ? 1 : 0

#   triggers_replace = [
#     var.ansible_version
#   ]

# #   # Install Ansible and dependencies on the HCP Terraform agent
# #   provisioner "local-exec" {
# #     command = <<-EOT
# #       set -e
# #       echo "=== Installing Ansible ${var.ansible_version} on agent ==="

# #       # Create virtual environment for isolation
# #       python3 -m venv /tmp/ansible-venv || python3 -m virtualenv /tmp/ansible-venv

# #       # Activate and install
# #       . /tmp/ansible-venv/bin/activate
# #       pip install --upgrade pip
# #       pip install ansible==${var.ansible_version}

# #       # Verify installation
# #       /tmp/ansible-venv/bin/ansible --version
# #       echo "=== Ansible installation complete ==="
# #     EOT
# #   }

# #   depends_on = [
# #     terraform_data.wait_for_vms
# #   ]
# # }

resource "terraform_data" "clone_kubespray" {
  count = var.enable_kubespray_deployment ? 1 : 0

  triggers_replace = [
    var.kubespray_version,
    var.kubernetes_version,
    # Force re-run when script logic changes
    "v9-python39-pip-fix"
  ]

  # Clone Kubespray repository on the agent
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "=== Setting up Python 3.9 virtual environment ==="

      # Verify Python 3.9 is available
      python3.9 --version || { echo "ERROR: Python 3.9 not found"; exit 1; }

      # Install virtualenv using python3.9 -m pip (pip3.9 may not be in PATH)
      python3.9 -m pip install --user virtualenv

      # Create isolated virtualenv with Python 3.9 to meet Kubespray requirements
      rm -rf /tmp/kubespray-venv
      python3.9 -m virtualenv /tmp/kubespray-venv
      . /tmp/kubespray-venv/bin/activate

      # Upgrade pip in virtualenv
      pip install --upgrade pip

      echo "=== Cloning Kubespray ${var.kubespray_version} ==="

      rm -rf /tmp/kubespray
      git clone --depth 1 --branch ${var.kubespray_version} https://github.com/kubernetes-sigs/kubespray.git /tmp/kubespray

      # Check Python version (should be 3.9)
      PYTHON_VERSION=$(python3.9 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
      echo "Python version: $PYTHON_VERSION"

      # Install Kubespray requirements into virtualenv
      echo "Installing Kubespray requirements..."
      pip install -r /tmp/kubespray/requirements.txt

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

resource "terraform_data" "run_kubespray" {
  count = var.enable_kubespray_deployment ? 1 : 0

  triggers_replace = [
    module.k8s_control_plane_01.ip_address,
    module.k8s_worker_01.ip_address,
    module.k8s_worker_02.ip_address,
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
    terraform_data.wait_for_vms,
    local_file.kubespray_inventory
  ]
}
