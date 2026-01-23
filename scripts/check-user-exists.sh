#!/usr/bin/env bash
# =============================================================================
# Check if User Exists on BCM Nodes
# =============================================================================
# This script is called by Terraform's external data source to check if the
# target user already exists on BCM nodes. Returns JSON indicating whether
# user creation should be skipped.
#
# Input (JSON via stdin):
#   {
#     "nodes": "node1,node2,node3",
#     "admin_user": "root",
#     "admin_key": "/path/to/key",
#     "target_username": "ansiblebcm"
#   }
#
# Output (JSON to stdout):
#   {
#     "user_exists": "true|false",
#     "checked_nodes": "3",
#     "nodes_with_user": "2"
#   }
# =============================================================================

set -e

# Parse JSON input
eval "$(jq -r '@sh "NODES=\(.nodes) ADMIN_USER=\(.admin_user) ADMIN_KEY=\(.admin_key) TARGET_USERNAME=\(.target_username)"')"

# SSH options for legacy BCM nodes
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o HostKeyAlgorithms=+ssh-rsa,ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa -o ConnectTimeout=10 -o BatchMode=yes"

# Convert comma-separated nodes to array
IFS=',' read -ra NODE_ARRAY <<< "$NODES"

TOTAL_NODES=${#NODE_ARRAY[@]}
NODES_WITH_USER=0
NODES_CHECKED=0

# Check each node
for NODE in "${NODE_ARRAY[@]}"; do
  # Try to check if user exists
  if ssh ${SSH_OPTS} -i "${ADMIN_KEY}" "${ADMIN_USER}@${NODE}" "id ${TARGET_USERNAME} >/dev/null 2>&1" 2>/dev/null; then
    ((NODES_WITH_USER++))
  fi
  ((NODES_CHECKED++))
done >&2  # Send progress to stderr (not captured by Terraform)

# Determine if user exists on all nodes
if [ "$NODES_WITH_USER" -eq "$TOTAL_NODES" ]; then
  USER_EXISTS="true"
elif [ "$NODES_WITH_USER" -eq 0 ]; then
  USER_EXISTS="false"
else
  # User exists on some but not all nodes - this is an error condition
  echo "ERROR: User ${TARGET_USERNAME} exists on ${NODES_WITH_USER}/${TOTAL_NODES} nodes. This is inconsistent." >&2
  echo "Please ensure the user either exists on ALL nodes or NONE." >&2
  USER_EXISTS="partial"
fi

# Output JSON result
jq -n \
  --arg user_exists "$USER_EXISTS" \
  --arg checked_nodes "$NODES_CHECKED" \
  --arg nodes_with_user "$NODES_WITH_USER" \
  '{user_exists: $user_exists, checked_nodes: $checked_nodes, nodes_with_user: $nodes_with_user}'
