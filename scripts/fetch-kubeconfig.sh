#!/bin/bash
# Fetch kubeconfig from Kubernetes control plane node
# This script is called by Terraform external data source

set -e

# Read JSON input from stdin
eval "$(jq -r '@sh "CONTROL_PLANE_IP=\(.control_plane_ip) SSH_USER=\(.ssh_user) SSH_PRIVATE_KEY=\(.ssh_private_key)"')"

# Validate inputs
if [ -z "$CONTROL_PLANE_IP" ] || [ "$CONTROL_PLANE_IP" == "null" ]; then
  echo '{"error": "control_plane_ip is required"}' >&2
  exit 1
fi

if [ -z "$SSH_USER" ] || [ "$SSH_USER" == "null" ]; then
  SSH_USER="ansiblebcm"
fi

# Create temporary SSH key file
SSH_KEY_FILE=$(mktemp)
echo "$SSH_PRIVATE_KEY" > "$SSH_KEY_FILE"
chmod 600 "$SSH_KEY_FILE"

# SSH options for legacy algorithm support (BCM nodes use older SSH)
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o HostKeyAlgorithms=+ssh-rsa,ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa -o ConnectTimeout=10"

# Fetch kubeconfig from control plane
KUBECONFIG_CONTENT=$(ssh $SSH_OPTS -i "$SSH_KEY_FILE" "${SSH_USER}@${CONTROL_PLANE_IP}" \
  "sudo cat /etc/kubernetes/admin.conf 2>/dev/null" 2>/dev/null || echo "")

# Cleanup
rm -f "$SSH_KEY_FILE"

# Check if we got kubeconfig
if [ -z "$KUBECONFIG_CONTENT" ]; then
  # Kubeconfig not yet available (cluster not ready)
  jq -n '{
    "kubeconfig": "",
    "status": "not_ready",
    "error": "Kubeconfig not yet available. Cluster may still be deploying."
  }'
else
  # Encode kubeconfig as base64 to safely pass through JSON
  KUBECONFIG_B64=$(echo "$KUBECONFIG_CONTENT" | base64 -w0 2>/dev/null || echo "$KUBECONFIG_CONTENT" | base64)
  
  # Replace the internal IP with the control plane IP for external access
  # Kubernetes admin.conf typically has 127.0.0.1 or internal cluster IP
  KUBECONFIG_FIXED=$(echo "$KUBECONFIG_CONTENT" | sed "s|server: https://127.0.0.1:|server: https://${CONTROL_PLANE_IP}:|g" | sed "s|server: https://localhost:|server: https://${CONTROL_PLANE_IP}:|g")
  KUBECONFIG_FIXED_B64=$(echo "$KUBECONFIG_FIXED" | base64 -w0 2>/dev/null || echo "$KUBECONFIG_FIXED" | base64)
  
  jq -n \
    --arg kubeconfig "$KUBECONFIG_FIXED_B64" \
    --arg status "ready" \
    '{
      "kubeconfig": $kubeconfig,
      "status": $status,
      "error": ""
    }'
fi
