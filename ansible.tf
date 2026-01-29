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
    local.vm_ip_addresses[count.index],
    # Re-trigger if SSH key changes
    tls_private_key.ssh_key.id
  ]

  # Ensure SSH key is generated and user is created before attempting SSH connection
  # User is automatically created via Ansible playbook (see user_creation.tf)
  depends_on = [
    tls_private_key.ssh_key,
    terraform_data.create_user
  ]

  # Use local-exec with SSH options to support legacy host key algorithms (ssh-rsa, ssh-dss)
  # Required for older BCM nodes that don't support newer key exchange algorithms
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Waiting for SSH on ${local.vm_ip_addresses[count.index]}..."
      
      # Retry loop for SSH connectivity (max 60 attempts, 5 seconds apart = 5 min timeout)
      for i in $(seq 1 60); do
        if ssh -o StrictHostKeyChecking=no \
               -o UserKnownHostsFile=/dev/null \
               -o HostKeyAlgorithms=+ssh-rsa,ssh-dss \
               -o PubkeyAcceptedAlgorithms=+ssh-rsa \
               -o ConnectTimeout=10 \
               -i ${local_sensitive_file.ssh_private_key.filename} \
               ${var.ssh_user}@${local.vm_ip_addresses[count.index]} \
               'echo "Node is ready for Ansible provisioning"' 2>/dev/null; then
          echo "SSH connection successful to ${local.vm_ip_addresses[count.index]}"
          exit 0
        fi
        echo "Attempt $i/60: SSH not ready, waiting 5 seconds..."
        sleep 5
      done
      
      echo "ERROR: SSH connection failed after 5 minutes to ${local.vm_ip_addresses[count.index]}"
      exit 1
    EOT
  }
}

# =============================================================================
# Ensure Required Python Version is Installed
# =============================================================================
# Kubespray v2.27+ requires Python 3.10+ for Ansible 9.x.
# This resource installs the required Python version if not already present.

resource "terraform_data" "install_python" {
  count = var.enable_kubespray_deployment ? 1 : 0

  triggers_replace = [
    var.python_version,
    # Force re-run when install logic changes
    "v1-auto-install"
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      PYTHON_CMD="python${var.python_version}"

      echo "=== Checking for Python ${var.python_version} ==="

      if command -v "$PYTHON_CMD" &>/dev/null; then
        echo "Python ${var.python_version} already installed: $($PYTHON_CMD --version)"
        # Verify venv module is available
        if "$PYTHON_CMD" -m venv --help &>/dev/null; then
          echo "venv module available"
          exit 0
        else
          echo "venv module missing, will install..."
        fi
      else
        echo "Python ${var.python_version} not found, installing..."
      fi

      # Detect OS and install
      if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
          ubuntu|debian)
            echo "Detected Debian/Ubuntu ($PRETTY_NAME)"
            sudo apt-get update -qq
            sudo apt-get install -y -qq software-properties-common
            sudo add-apt-repository -y ppa:deadsnakes/ppa
            sudo apt-get update -qq
            sudo apt-get install -y -qq "python${var.python_version}" "python${var.python_version}-venv" "python${var.python_version}-dev"
            ;;
          rhel|centos|rocky|almalinux)
            echo "Detected RHEL-family ($PRETTY_NAME)"
            sudo dnf install -y "python${var.python_version}" "python${var.python_version}-devel" || \
            sudo yum install -y "python${var.python_version}" "python${var.python_version}-devel"
            ;;
          *)
            echo "ERROR: Unsupported OS '$ID'. Install Python ${var.python_version} manually."
            exit 1
            ;;
        esac
      else
        echo "ERROR: Cannot detect OS (no /etc/os-release). Install Python ${var.python_version} manually."
        exit 1
      fi

      # Verify installation
      "$PYTHON_CMD" --version || { echo "ERROR: Python ${var.python_version} installation failed"; exit 1; }
      echo "=== Python ${var.python_version} installed successfully ==="
    EOT
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
    var.python_version,
    # Force re-run when script logic changes
    "v12-configurable-python"
  ]

  # Clone Kubespray repository on the agent
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      PYTHON_CMD="python${var.python_version}"

      echo "=== Setting up Python ${var.python_version} virtual environment ==="

      # Verify Python is available (should be installed by install_python resource)
      $PYTHON_CMD --version || { echo "ERROR: Python ${var.python_version} not found. Run terraform apply again or install manually."; exit 1; }

      # Use built-in venv module instead of virtualenv (avoids extra install and memory usage)
      echo "Removing old virtualenv if exists..."
      rm -rf /tmp/kubespray-venv

      echo "Creating virtualenv with $PYTHON_CMD -m venv..."
      $PYTHON_CMD -m venv /tmp/kubespray-venv

      echo "Activating virtualenv..."
      . /tmp/kubespray-venv/bin/activate

      # Upgrade pip with constraints to reduce memory
      echo "Upgrading pip..."
      pip install --upgrade pip --no-cache-dir

      echo "=== Cloning Kubespray ${var.kubespray_version} ==="

      rm -rf /tmp/kubespray
      git clone --depth 1 --branch ${var.kubespray_version} https://github.com/kubernetes-sigs/kubespray.git /tmp/kubespray

      # Check Python version
      PYTHON_VERSION=$($PYTHON_CMD -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
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

  depends_on = [
    terraform_data.install_python
  ]
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

      # Configure SSH options with legacy algorithm support for older BCM nodes
      export ANSIBLE_HOST_KEY_CHECKING=False
      export ANSIBLE_SSH_ARGS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o HostKeyAlgorithms=+ssh-rsa,ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa"

      echo "=== Starting Kubespray cluster deployment ==="

      # Use ansible from virtualenv to avoid system ansible 2.12 conflicts
      echo "=== Using virtualenv ansible ==="
      /tmp/kubespray-venv/bin/ansible --version

      cd /tmp/kubespray

      # Write extra config for Kubespray
      # nginx_kube_apiserver_healthcheck_port: BCM Command Manager uses port 8081,
      # so we use 8082 for the nginx-proxy healthcheck to avoid conflicts on worker nodes
      cat > /tmp/kubespray_registry_config.yml << 'REGCONFIG'
containerd_registries_mirrors:
  - prefix: docker.io
    mirrors:
      - host: https://mirror.gcr.io
        capabilities: ["pull", "resolve"]
        skip_verify: false
      - host: https://registry-1.docker.io
        capabilities: ["pull", "resolve"]
        skip_verify: false
REGCONFIG

      /tmp/kubespray-venv/bin/ansible-playbook -i inventory/mycluster/hosts.yml cluster.yml \
        -b -v \
        --private-key=/tmp/kubespray_ssh_key \
        -e "kube_version=${var.kubernetes_version}" \
        -e "kube_network_plugin=${var.cni_plugin}" \
        -e "kube_pods_subnet=${var.pod_network_cidr}" \
        -e "kube_service_addresses=${var.service_network_cidr}" \
        -e "cluster_name=${var.cluster_name}" \
        -e "ansible_user=${var.ssh_user}" \
        -e "ansible_ssh_private_key_file=/tmp/kubespray_ssh_key" \
        -e "nginx_kube_apiserver_healthcheck_port=8082" \
        -e "@/tmp/kubespray_registry_config.yml"

      echo "=== Kubespray deployment completed ==="

      # Cleanup sensitive files
      rm -f /tmp/kubespray_ssh_key
      rm -f /tmp/kubespray_registry_config.yml
    EOT
  }

  depends_on = [
    terraform_data.clone_kubespray,
    terraform_data.wait_for_nodes,
    local_file.kubespray_inventory
  ]
}
