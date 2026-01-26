# GPU Node Preparation
# Feature: BCM-based Kubernetes Deployment with GPU Support
#
# This configuration prepares GPU worker nodes for the NVIDIA GPU Operator:
# 1. Validates prerequisites (disk space, connectivity) before GPU Operator
# 2. Labels GPU nodes for GPU Operator targeting
#
# Prerequisites (must be met before deployment):
# - GPU nodes must have at least 10GB available for containerd storage
# - If /var is too small, relocate containerd to a larger partition manually
#   using: scripts/relocate-containerd.sh <node> /local
# - See docs/GPU_OPERATOR_PREREQUISITES.md for full requirements

# =============================================================================
# Variables for GPU Node Configuration
# =============================================================================

variable "gpu_worker_nodes" {
  description = "List of GPU worker node hostnames (e.g., dgx-05, dgx-06)"
  type        = list(string)
  default     = []
}

variable "min_containerd_space_gb" {
  description = "Minimum required space in GB for containerd storage on GPU nodes"
  type        = number
  default     = 10
}

variable "enable_gpu_node_labels" {
  description = "Enable automatic GPU node labeling"
  type        = bool
  default     = true
}

variable "enable_gpu_prereq_validation" {
  description = "Enable GPU node prerequisite validation before GPU Operator install"
  type        = bool
  default     = true
}

# =============================================================================
# Locals
# =============================================================================

locals {
  # Use gpu_worker_nodes if specified, otherwise fall back to worker_nodes
  effective_gpu_nodes = length(var.gpu_worker_nodes) > 0 ? var.gpu_worker_nodes : var.worker_nodes

  # Get production IPs for GPU nodes
  gpu_node_ips = {
    for hostname in local.effective_gpu_nodes :
    hostname => lookup(var.node_production_ips, hostname, hostname)
  }
}

# =============================================================================
# GPU Node Labels
# Labels GPU worker nodes so the GPU Operator can target them.
# The GPU Operator's Node Feature Discovery (NFD) will add more labels,
# but these explicit labels ensure proper targeting.
# =============================================================================

resource "terraform_data" "label_gpu_nodes" {
  for_each = var.enable_gpu_node_labels && var.enable_ansible ? toset(local.effective_gpu_nodes) : toset([])

  triggers_replace = [
    each.key,
    # Re-run if labeling logic changes
    "v1-gpu-labels"
  ]

  depends_on = [
    terraform_data.run_kubespray
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      NODE="${each.key}"
      KUBECONFIG_PATH="${path.module}/kubeconfig"

      echo "=== Labeling GPU node: $NODE ==="

      # Check if kubeconfig exists
      if [ ! -f "$KUBECONFIG_PATH" ]; then
        echo "ERROR: kubeconfig not found at $KUBECONFIG_PATH"
        echo "Kubespray may not have completed successfully"
        exit 1
      fi

      # Apply GPU-related labels
      export KUBECONFIG="$KUBECONFIG_PATH"

      # nvidia.com/gpu.present - signals this is a GPU node
      kubectl label node "$NODE" nvidia.com/gpu.present=true --overwrite || true

      # node-role.kubernetes.io/gpu - role label for scheduling
      kubectl label node "$NODE" node-role.kubernetes.io/gpu=worker --overwrite || true

      # Feature gate for GPU workloads
      kubectl label node "$NODE" feature.node.kubernetes.io/gpu=true --overwrite || true

      echo "=== GPU labels applied to $NODE ==="
      kubectl get node "$NODE" --show-labels | grep -E "nvidia|gpu" || true
    EOT
  }
}

# =============================================================================
# Pre-requisite Validation
# Validates that GPU nodes meet requirements before GPU Operator installation.
# This check runs BEFORE GPU Operator and will FAIL if nodes don't have
# sufficient disk space. See docs/GPU_OPERATOR_PREREQUISITES.md for fixes.
# =============================================================================

resource "terraform_data" "validate_gpu_prereqs" {
  count = var.enable_gpu_prereq_validation && var.enable_ansible && length(local.effective_gpu_nodes) > 0 ? 1 : 0

  triggers_replace = [
    join(",", local.effective_gpu_nodes),
    var.min_containerd_space_gb,
    # Re-run if validation logic changes
    "v2-prereq-check"
  ]

  depends_on = [
    terraform_data.run_kubespray
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "=== Validating GPU Node Prerequisites ==="

      SSH_KEY="${local_sensitive_file.ssh_private_key.filename}"
      SSH_USER="${var.ssh_user}"
      MIN_SPACE_GB=${var.min_containerd_space_gb}
      FAILED=0

      ssh_cmd() {
        local node_ip="$1"
        shift
        ssh -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=30 \
            -o LogLevel=ERROR \
            -i "$SSH_KEY" \
            "$SSH_USER@$node_ip" "$@"
      }

      %{for hostname, ip in local.gpu_node_ips}
      echo ""
      echo "--- Checking ${hostname} (${ip}) ---"

      # Check SSH connectivity
      if ! ssh_cmd "${ip}" "echo ok" | grep -q ok; then
        echo "FAIL: Cannot SSH to ${hostname}"
        FAILED=1
        continue
      fi
      echo "PASS: SSH connectivity"

      # Check containerd storage space
      CONTAINERD_PATH=$(ssh_cmd "${ip}" "readlink -f /var/lib/containerd 2>/dev/null || echo /var/lib/containerd")
      AVAIL_KB=$(ssh_cmd "${ip}" "df '$CONTAINERD_PATH' 2>/dev/null | tail -1 | awk '{print \$4}'" 2>/dev/null || echo "0")
      AVAIL_GB=$((AVAIL_KB / 1024 / 1024))

      if [ "$AVAIL_GB" -ge "$MIN_SPACE_GB" ]; then
        echo "PASS: Containerd storage has $${AVAIL_GB}GB available"
      else
        echo "FAIL: Containerd storage only has $${AVAIL_GB}GB (need $${MIN_SPACE_GB}GB)"
        FAILED=1
      fi

      # Check containerd is running
      if ssh_cmd "${ip}" "systemctl is-active containerd" | grep -q active; then
        echo "PASS: Containerd is running"
      else
        echo "FAIL: Containerd is not running"
        FAILED=1
      fi

      %{endfor}

      echo ""
      echo "=== Validation Complete ==="

      if [ "$FAILED" -eq 1 ]; then
        echo "ERROR: One or more GPU nodes failed validation"
        exit 1
      fi

      echo "SUCCESS: All GPU nodes passed validation"
    EOT
  }
}

# =============================================================================
# Outputs
# =============================================================================

output "gpu_nodes_prepared" {
  description = "List of GPU nodes that have been prepared"
  value       = local.effective_gpu_nodes
}

output "gpu_prereq_validation_enabled" {
  description = "Whether GPU prerequisite validation is enabled"
  value       = var.enable_gpu_prereq_validation
}

output "gpu_node_labels_enabled" {
  description = "Whether GPU node labeling is enabled"
  value       = var.enable_gpu_node_labels
}
