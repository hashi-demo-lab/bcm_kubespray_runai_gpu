#!/bin/bash
# =============================================================================
# Configure Helm for NFS Environments
# =============================================================================
# Source this script to configure Helm to use local filesystem paths instead
# of the home directory, which may be NFS-mounted and not support file locking.
#
# Usage:
#   source ./scripts/setup-helm-nfs.sh
#
# This sets environment variables that tell Helm to use /tmp for caches and
# configuration, bypassing the NFS file locking limitation.
# =============================================================================

export HELM_CACHE_HOME=/tmp/helm-cache
export HELM_CONFIG_HOME=/tmp/helm-config
export HELM_DATA_HOME=/tmp/helm-data

# Create directories if they don't exist
mkdir -p "$HELM_CACHE_HOME" "$HELM_CONFIG_HOME" "$HELM_DATA_HOME"

echo "Helm configured for NFS environment:"
echo "  HELM_CACHE_HOME=$HELM_CACHE_HOME"
echo "  HELM_CONFIG_HOME=$HELM_CONFIG_HOME"
echo "  HELM_DATA_HOME=$HELM_DATA_HOME"
echo ""
echo "These settings will persist for this shell session."
echo "To use with sudo, pass the variables explicitly:"
echo ""
echo "  sudo KUBECONFIG=/etc/kubernetes/admin.conf \\"
echo "       HELM_CACHE_HOME=\$HELM_CACHE_HOME \\"
echo "       HELM_CONFIG_HOME=\$HELM_CONFIG_HOME \\"
echo "       HELM_DATA_HOME=\$HELM_DATA_HOME \\"
echo "       helm install ..."
