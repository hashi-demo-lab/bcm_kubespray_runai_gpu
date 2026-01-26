#!/bin/bash
# =============================================================================
# Install NVIDIA GPU Operator with Pre-requisite Checks
# =============================================================================
# This script runs pre-requisite checks and then installs the GPU Operator.
#
# Usage:
#   ./install-gpu-operator.sh [--skip-checks] [--fix]
#
# Options:
#   --skip-checks   Skip pre-requisite checks (use with caution)
#   --fix           Attempt to fix issues during pre-req checks
#
# Environment Variables:
#   GPU_NODES       Space-separated list of GPU node hostnames (default: dgx-05 dgx-06)
#   SSH_USER        SSH user for node access (default: ibm)
#   SSH_KEY         Path to SSH private key (default: ./generated_ssh_key)
#   KUBECONFIG      Path to kubeconfig (default: /etc/kubernetes/admin.conf)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Parse arguments
SKIP_CHECKS=false
FIX_MODE=""

for arg in "$@"; do
    case $arg in
        --skip-checks)
            SKIP_CHECKS=true
            shift
            ;;
        --fix)
            FIX_MODE="--fix"
            shift
            ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=============================================="
echo "NVIDIA GPU Operator Installation"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# Step 1: Run Pre-requisite Checks
# -----------------------------------------------------------------------------
if ! $SKIP_CHECKS; then
    echo "Step 1: Running pre-requisite checks..."
    echo ""

    if ! "${SCRIPT_DIR}/check-gpu-operator-prereqs.sh" $FIX_MODE; then
        echo ""
        echo -e "${RED}Pre-requisite checks failed!${NC}"
        echo ""
        echo "Options:"
        echo "  1. Fix the issues and re-run this script"
        echo "  2. Run with --fix to attempt automatic fixes:"
        echo "     ./install-gpu-operator.sh --fix"
        echo "  3. Run with --skip-checks to bypass (not recommended):"
        echo "     ./install-gpu-operator.sh --skip-checks"
        echo ""
        exit 1
    fi
else
    echo -e "${YELLOW}Skipping pre-requisite checks (--skip-checks)${NC}"
    echo ""
fi

# -----------------------------------------------------------------------------
# Step 2: Configure Helm for NFS if needed
# -----------------------------------------------------------------------------
echo "Step 2: Configuring Helm..."

HOME_FS_TYPE=$(df -T ~ 2>/dev/null | tail -1 | awk '{print $2}')
if [[ "$HOME_FS_TYPE" == "nfs" || "$HOME_FS_TYPE" == "nfs4" ]]; then
    echo "Home directory is NFS-mounted, configuring Helm..."
    export HELM_CACHE_HOME=/tmp/helm-cache
    export HELM_CONFIG_HOME=/tmp/helm-config
    export HELM_DATA_HOME=/tmp/helm-data
    mkdir -p "$HELM_CACHE_HOME" "$HELM_CONFIG_HOME" "$HELM_DATA_HOME"
fi

# -----------------------------------------------------------------------------
# Step 3: Add NVIDIA Helm Repository
# -----------------------------------------------------------------------------
echo "Step 3: Adding NVIDIA Helm repository..."

sudo ${KUBECONFIG:+KUBECONFIG=$KUBECONFIG} \
     ${HELM_CACHE_HOME:+HELM_CACHE_HOME=$HELM_CACHE_HOME} \
     ${HELM_CONFIG_HOME:+HELM_CONFIG_HOME=$HELM_CONFIG_HOME} \
     ${HELM_DATA_HOME:+HELM_DATA_HOME=$HELM_DATA_HOME} \
     helm repo add nvidia https://helm.ngc.nvidia.com/nvidia 2>/dev/null || true

sudo ${KUBECONFIG:+KUBECONFIG=$KUBECONFIG} \
     ${HELM_CACHE_HOME:+HELM_CACHE_HOME=$HELM_CACHE_HOME} \
     ${HELM_CONFIG_HOME:+HELM_CONFIG_HOME=$HELM_CONFIG_HOME} \
     ${HELM_DATA_HOME:+HELM_DATA_HOME=$HELM_DATA_HOME} \
     helm repo update

# -----------------------------------------------------------------------------
# Step 4: Create Namespace
# -----------------------------------------------------------------------------
echo "Step 4: Creating gpu-operator namespace..."

sudo ${KUBECONFIG:+KUBECONFIG=$KUBECONFIG} \
     kubectl create namespace gpu-operator 2>/dev/null || true

# -----------------------------------------------------------------------------
# Step 5: Check for existing NVIDIA drivers
# -----------------------------------------------------------------------------
echo "Step 5: Checking for pre-installed NVIDIA drivers..."

DRIVER_ENABLED="true"
GPU_NODES="${GPU_NODES:-dgx-05 dgx-06}"
SSH_USER="${SSH_USER:-ibm}"
SSH_KEY="${SSH_KEY:-${PROJECT_DIR}/generated_ssh_key}"

for node in $GPU_NODES; do
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
           -o ConnectTimeout=5 -o LogLevel=ERROR \
           ${SSH_KEY:+-i "$SSH_KEY"} \
           "${SSH_USER}@${node}" "which nvidia-smi && nvidia-smi" 2>/dev/null | grep -qi "nvidia"; then
        echo "  $node: NVIDIA drivers detected"
        DRIVER_ENABLED="false"
    else
        echo "  $node: No NVIDIA drivers (will install via GPU Operator)"
        DRIVER_ENABLED="true"
        break
    fi
done

echo ""
echo "Driver installation: $DRIVER_ENABLED"

# -----------------------------------------------------------------------------
# Step 6: Install GPU Operator
# -----------------------------------------------------------------------------
echo ""
echo "Step 6: Installing NVIDIA GPU Operator..."
echo ""

KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

sudo KUBECONFIG="$KUBECONFIG" \
     ${HELM_CACHE_HOME:+HELM_CACHE_HOME=$HELM_CACHE_HOME} \
     ${HELM_CONFIG_HOME:+HELM_CONFIG_HOME=$HELM_CONFIG_HOME} \
     ${HELM_DATA_HOME:+HELM_DATA_HOME=$HELM_DATA_HOME} \
     helm upgrade --install gpu-operator nvidia/gpu-operator \
     --namespace gpu-operator \
     --set driver.enabled=${DRIVER_ENABLED} \
     --set toolkit.enabled=true \
     --set devicePlugin.enabled=true \
     --set mig.strategy=single \
     --wait --timeout 15m

# -----------------------------------------------------------------------------
# Step 7: Verify Installation
# -----------------------------------------------------------------------------
echo ""
echo "Step 7: Verifying installation..."
echo ""

# Wait for pods to start
sleep 10

sudo KUBECONFIG="$KUBECONFIG" kubectl get pods -n gpu-operator

echo ""
echo -e "${GREEN}GPU Operator installation complete!${NC}"
echo ""
echo "Monitor pod status with:"
echo "  sudo KUBECONFIG=$KUBECONFIG kubectl get pods -n gpu-operator -w"
echo ""
echo "Check GPU resources with:"
echo "  sudo KUBECONFIG=$KUBECONFIG kubectl describe nodes | grep -A5 nvidia"
