#!/bin/bash
# Setup KUBECONFIG environment variable persistently
# Run this script after cluster deployment to configure kubectl access

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
KUBECONFIG_PATH="${REPO_DIR}/kubeconfig"

# Check if kubeconfig exists
if [[ ! -f "$KUBECONFIG_PATH" ]]; then
    echo "ERROR: kubeconfig not found at $KUBECONFIG_PATH"
    echo "Run 'terraform apply' in the root directory first to generate the kubeconfig."
    exit 1
fi

# Determine which shell config file to use
if [[ -f "$HOME/.bashrc" ]]; then
    SHELL_RC="$HOME/.bashrc"
elif [[ -f "$HOME/.bash_profile" ]]; then
    SHELL_RC="$HOME/.bash_profile"
elif [[ -f "$HOME/.zshrc" ]]; then
    SHELL_RC="$HOME/.zshrc"
else
    echo "ERROR: Could not find shell config file (.bashrc, .bash_profile, or .zshrc)"
    exit 1
fi

# Check if KUBECONFIG is already set in the shell config
if grep -q "export KUBECONFIG=" "$SHELL_RC" 2>/dev/null; then
    echo "KUBECONFIG already configured in $SHELL_RC"
    echo "Current setting:"
    grep "export KUBECONFIG=" "$SHELL_RC"
    echo ""
    read -p "Do you want to update it to $KUBECONFIG_PATH? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Remove old KUBECONFIG line and add new one
        sed -i.bak '/export KUBECONFIG=/d' "$SHELL_RC"
        echo "export KUBECONFIG=$KUBECONFIG_PATH" >> "$SHELL_RC"
        echo "Updated KUBECONFIG in $SHELL_RC"
    else
        echo "Skipping update."
        exit 0
    fi
else
    # Add KUBECONFIG export
    echo "" >> "$SHELL_RC"
    echo "# Kubernetes configuration (added by bcm_kubespray_runai_gpu)" >> "$SHELL_RC"
    echo "export KUBECONFIG=$KUBECONFIG_PATH" >> "$SHELL_RC"
    echo "Added KUBECONFIG to $SHELL_RC"
fi

# Also set for current session
export KUBECONFIG="$KUBECONFIG_PATH"

echo ""
echo "KUBECONFIG configured successfully!"
echo ""
echo "For current session, run:"
echo "  source $SHELL_RC"
echo ""
echo "Or simply open a new terminal."
echo ""

# Test kubectl access
echo "Testing kubectl access..."
if kubectl cluster-info &>/dev/null; then
    echo "✓ kubectl is working!"
    kubectl get nodes
else
    echo "✗ kubectl test failed. Check that the cluster is running."
fi
