#!/bin/bash
# =============================================================================
# GPU Operator Pre-requisite Checks
# =============================================================================
# Run this script before installing the NVIDIA GPU Operator to verify all
# requirements are met on the GPU worker nodes.
#
# Usage:
#   ./check-gpu-operator-prereqs.sh [--fix]
#
# Options:
#   --fix    Attempt to automatically fix issues (requires sudo on nodes)
#
# Exit Codes:
#   0 - All checks passed
#   1 - One or more checks failed
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration - Override via environment variables if needed
GPU_NODES="${GPU_NODES:-dgx-05 dgx-06}"
SSH_USER="${SSH_USER:-ibm}"
SSH_KEY="${SSH_KEY:-${PROJECT_DIR}/generated_ssh_key}"
MIN_CONTAINERD_SPACE_GB="${MIN_CONTAINERD_SPACE_GB:-10}"
CONTAINERD_RELOCATE_PATH="${CONTAINERD_RELOCATE_PATH:-/local/containerd}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track failures
FAILED_CHECKS=0
FIX_MODE=false

# Parse arguments
if [[ "$1" == "--fix" ]]; then
    FIX_MODE=true
    echo -e "${YELLOW}Running in FIX mode - will attempt to remediate issues${NC}"
    echo ""
fi

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
    echo ""
    echo "=============================================="
    echo "$1"
    echo "=============================================="
}

print_check() {
    echo -n "  [CHECK] $1... "
}

print_pass() {
    echo -e "${GREEN}PASS${NC}"
}

print_fail() {
    echo -e "${RED}FAIL${NC}"
    ((FAILED_CHECKS++))
}

print_warn() {
    echo -e "${YELLOW}WARN${NC}"
}

print_info() {
    echo -e "          $1"
}

ssh_cmd() {
    local node="$1"
    local cmd="$2"
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -o LogLevel=ERROR \
        ${SSH_KEY:+-i "$SSH_KEY"} \
        "${SSH_USER}@${node}" "$cmd" 2>/dev/null
}

# =============================================================================
# Pre-requisite Checks
# =============================================================================

print_header "GPU Operator Pre-requisite Checks"
echo "GPU Nodes: $GPU_NODES"
echo "SSH User: $SSH_USER"
echo "Min Containerd Space: ${MIN_CONTAINERD_SPACE_GB}GB"
echo ""

# -----------------------------------------------------------------------------
# Check 1: Helm NFS Compatibility
# -----------------------------------------------------------------------------
print_header "1. Helm NFS Compatibility"

print_check "Checking if home directory is NFS-mounted"
HOME_FS_TYPE=$(df -T ~ 2>/dev/null | tail -1 | awk '{print $2}')

if [[ "$HOME_FS_TYPE" == "nfs" || "$HOME_FS_TYPE" == "nfs4" ]]; then
    print_warn
    print_info "Home directory is NFS-mounted ($HOME_FS_TYPE)"
    print_info "Helm requires local filesystem for file locking"
    print_info ""
    print_info "REMEDIATION: Set these environment variables before running helm:"
    print_info "  export HELM_CACHE_HOME=/tmp/helm-cache"
    print_info "  export HELM_CONFIG_HOME=/tmp/helm-config"
    print_info "  export HELM_DATA_HOME=/tmp/helm-data"

    # Create a helper script
    if $FIX_MODE; then
        cat > "${PROJECT_DIR}/scripts/setup-helm-nfs.sh" << 'EOF'
#!/bin/bash
# Source this file to configure Helm for NFS environments
export HELM_CACHE_HOME=/tmp/helm-cache
export HELM_CONFIG_HOME=/tmp/helm-config
export HELM_DATA_HOME=/tmp/helm-data
mkdir -p "$HELM_CACHE_HOME" "$HELM_CONFIG_HOME" "$HELM_DATA_HOME"
echo "Helm configured for NFS environment"
EOF
        chmod +x "${PROJECT_DIR}/scripts/setup-helm-nfs.sh"
        print_info "Created: scripts/setup-helm-nfs.sh"
    fi
else
    print_pass
    print_info "Home directory filesystem: $HOME_FS_TYPE (local)"
fi

# -----------------------------------------------------------------------------
# Check 2: KUBECONFIG Access
# -----------------------------------------------------------------------------
print_header "2. KUBECONFIG Access"

print_check "Checking KUBECONFIG accessibility"
if [[ -n "$KUBECONFIG" && -r "$KUBECONFIG" ]]; then
    print_pass
    print_info "KUBECONFIG=$KUBECONFIG is readable"
elif [[ -r "/etc/kubernetes/admin.conf" ]]; then
    print_pass
    print_info "/etc/kubernetes/admin.conf is readable"
elif sudo test -r "/etc/kubernetes/admin.conf" 2>/dev/null; then
    print_warn
    print_info "/etc/kubernetes/admin.conf requires sudo access"
    print_info ""
    print_info "REMEDIATION: Run kubectl/helm with sudo:"
    print_info "  sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes"
else
    print_fail
    print_info "Cannot access Kubernetes admin config"
    print_info "Ensure you're running on a control plane node"
fi

# -----------------------------------------------------------------------------
# Check 3: SSH Connectivity to GPU Nodes
# -----------------------------------------------------------------------------
print_header "3. SSH Connectivity to GPU Nodes"

for node in $GPU_NODES; do
    print_check "SSH to $node"
    if ssh_cmd "$node" "echo ok" | grep -q "ok"; then
        print_pass
    else
        print_fail
        print_info "Cannot SSH to $node as $SSH_USER"
        print_info "Check SSH key and connectivity"
    fi
done

# -----------------------------------------------------------------------------
# Check 4: NVIDIA Driver Status on GPU Nodes
# -----------------------------------------------------------------------------
print_header "4. NVIDIA Driver Status on GPU Nodes"

DRIVERS_INSTALLED=true
for node in $GPU_NODES; do
    print_check "NVIDIA drivers on $node"

    # Check for nvidia-smi
    if ssh_cmd "$node" "which nvidia-smi" | grep -q nvidia-smi; then
        # Verify nvidia-smi works
        if ssh_cmd "$node" "nvidia-smi --query-gpu=name --format=csv,noheader" 2>/dev/null | grep -qi "gpu\|nvidia\|tesla\|a100\|v100\|h100"; then
            print_pass
            GPU_NAME=$(ssh_cmd "$node" "nvidia-smi --query-gpu=name --format=csv,noheader" 2>/dev/null | head -1)
            print_info "GPU detected: $GPU_NAME"
        else
            print_warn
            print_info "nvidia-smi exists but GPU not responding"
            DRIVERS_INSTALLED=false
        fi
    else
        print_warn
        print_info "NVIDIA drivers not installed"
        DRIVERS_INSTALLED=false

        # Check for kernel modules
        if ssh_cmd "$node" "lsmod | grep nvidia" | grep -q nvidia; then
            print_info "nvidia kernel module is loaded"
        else
            print_info "No nvidia kernel modules loaded"
        fi
    fi
done

if ! $DRIVERS_INSTALLED; then
    echo ""
    print_info "NOTE: GPU Operator will be configured with driver.enabled=true"
    print_info "      to install NVIDIA drivers as containers."
fi

# -----------------------------------------------------------------------------
# Check 5: Disk Space for Containerd on GPU Nodes
# -----------------------------------------------------------------------------
print_header "5. Disk Space for Containerd on GPU Nodes"

for node in $GPU_NODES; do
    print_check "Containerd storage space on $node"

    # Get current containerd path (might be symlink)
    CONTAINERD_PATH=$(ssh_cmd "$node" "readlink -f /var/lib/containerd 2>/dev/null || echo /var/lib/containerd")
    CONTAINERD_MOUNT=$(ssh_cmd "$node" "df '$CONTAINERD_PATH' 2>/dev/null | tail -1")

    AVAIL_KB=$(echo "$CONTAINERD_MOUNT" | awk '{print $4}')
    AVAIL_GB=$((AVAIL_KB / 1024 / 1024))
    MOUNT_POINT=$(echo "$CONTAINERD_MOUNT" | awk '{print $6}')

    if [[ $AVAIL_GB -ge $MIN_CONTAINERD_SPACE_GB ]]; then
        print_pass
        print_info "Available: ${AVAIL_GB}GB on $MOUNT_POINT (min: ${MIN_CONTAINERD_SPACE_GB}GB)"
    else
        print_fail
        print_info "Available: ${AVAIL_GB}GB on $MOUNT_POINT (need: ${MIN_CONTAINERD_SPACE_GB}GB)"

        # Check for /local partition
        LOCAL_AVAIL=$(ssh_cmd "$node" "df /local 2>/dev/null | tail -1 | awk '{print \$4}'" 2>/dev/null)
        LOCAL_AVAIL_GB=$((LOCAL_AVAIL / 1024 / 1024))

        if [[ $LOCAL_AVAIL_GB -ge $MIN_CONTAINERD_SPACE_GB ]]; then
            print_info ""
            print_info "/local partition has ${LOCAL_AVAIL_GB}GB available"
            print_info ""
            print_info "REMEDIATION: Relocate containerd to /local:"
            print_info "  ./scripts/relocate-containerd.sh $node /local"

            if $FIX_MODE; then
                echo ""
                echo -e "${YELLOW}Attempting to relocate containerd on $node...${NC}"
                ssh_cmd "$node" "sudo bash -c '
                    set -e
                    systemctl stop containerd
                    mkdir -p /local/containerd
                    rsync -av /var/lib/containerd/ /local/containerd/
                    mv /var/lib/containerd /var/lib/containerd.old
                    ln -s /local/containerd /var/lib/containerd
                    systemctl start containerd
                    rm -rf /var/lib/containerd.old
                    echo Containerd relocated successfully
                '"
                print_info "Containerd relocated to /local on $node"
            fi
        else
            print_info ""
            print_info "No alternative partition found with sufficient space"
            print_info "Consider adding storage or cleaning up unused images"
        fi
    fi
done

# -----------------------------------------------------------------------------
# Check 6: Kernel Headers (for driver compilation)
# -----------------------------------------------------------------------------
print_header "6. Kernel Headers on GPU Nodes"

for node in $GPU_NODES; do
    print_check "Kernel headers on $node"

    KERNEL_VERSION=$(ssh_cmd "$node" "uname -r")

    if ssh_cmd "$node" "ls /lib/modules/$KERNEL_VERSION/build 2>/dev/null" | grep -q .; then
        print_pass
        print_info "Kernel headers present for $KERNEL_VERSION"
    else
        print_warn
        print_info "Kernel headers may not be installed for $KERNEL_VERSION"
        print_info "GPU Operator driver compilation may fail"
        print_info ""
        print_info "REMEDIATION (if needed):"
        print_info "  apt-get install linux-headers-$KERNEL_VERSION"
    fi
done

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
print_header "Summary"

if [[ $FAILED_CHECKS -eq 0 ]]; then
    echo -e "${GREEN}All critical checks passed!${NC}"
    echo ""
    echo "You can proceed with GPU Operator installation:"
    echo ""
    if [[ "$HOME_FS_TYPE" == "nfs" || "$HOME_FS_TYPE" == "nfs4" ]]; then
        echo "  # Configure Helm for NFS"
        echo "  source ./scripts/setup-helm-nfs.sh"
        echo ""
    fi
    echo "  # Install GPU Operator"
    echo "  sudo KUBECONFIG=/etc/kubernetes/admin.conf \\"
    if [[ "$HOME_FS_TYPE" == "nfs" || "$HOME_FS_TYPE" == "nfs4" ]]; then
        echo "       HELM_CACHE_HOME=\$HELM_CACHE_HOME \\"
        echo "       HELM_CONFIG_HOME=\$HELM_CONFIG_HOME \\"
        echo "       HELM_DATA_HOME=\$HELM_DATA_HOME \\"
    fi
    echo "       helm install gpu-operator nvidia/gpu-operator \\"
    echo "       --namespace gpu-operator \\"
    echo "       --create-namespace \\"
    if ! $DRIVERS_INSTALLED; then
        echo "       --set driver.enabled=true \\"
    else
        echo "       --set driver.enabled=false \\"
    fi
    echo "       --set toolkit.enabled=true \\"
    echo "       --set devicePlugin.enabled=true \\"
    echo "       --set mig.strategy=single \\"
    echo "       --wait --timeout 15m"
    echo ""
    exit 0
else
    echo -e "${RED}$FAILED_CHECKS critical check(s) failed!${NC}"
    echo ""
    echo "Please resolve the issues above before installing the GPU Operator."
    echo ""
    echo "To attempt automatic fixes, run:"
    echo "  ./scripts/check-gpu-operator-prereqs.sh --fix"
    echo ""
    exit 1
fi
