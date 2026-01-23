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
#     "nodes_with_user": "2",
#     "check_method": "ssh|skipped"
#   }
# =============================================================================

# Don't exit on error - we need to handle failures gracefully
set +e

# Check for jq
if ! command -v jq &> /dev/null; then
  echo '{"user_exists": "false", "checked_nodes": "0", "nodes_with_user": "0", "check_method": "error", "error": "jq not found"}'
  exit 0
fi

# Parse JSON input
eval "$(jq -r '@sh "NODES=\(.nodes) ADMIN_USER=\(.admin_user) ADMIN_KEY=\(.admin_key) TARGET_USERNAME=\(.target_username)"')"

# Expand tilde in admin key path
ADMIN_KEY="${ADMIN_KEY/#\~/$HOME}"

# Check if admin key exists
if [ ! -f "$ADMIN_KEY" ]; then
  echo "Admin SSH key not found at: $ADMIN_KEY" >&2
  jq -n \
    --arg user_exists "false" \
    --arg checked_nodes "0" \
    --arg nodes_with_user "0" \
    --arg check_method "skipped" \
    --arg error "Admin SSH key not found at $ADMIN_KEY" \
    '{user_exists: $user_exists, checked_nodes: $checked_nodes, nodes_with_user: $nodes_with_user, check_method: $check_method, error: $error}'
  exit 0
fi

echo "Checking for user '${TARGET_USERNAME}' on nodes..." >&2
echo "Admin key: ${ADMIN_KEY}" >&2

# SSH options for legacy BCM nodes
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o HostKeyAlgorithms=+ssh-rsa,ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa -o ConnectTimeout=10 -o BatchMode=yes"

# Convert comma-separated nodes to array
IFS=',' read -ra NODE_ARRAY <<< "$NODES"

TOTAL_NODES=${#NODE_ARRAY[@]}
NODES_WITH_USER=0
NODES_CHECKED=0
SSH_FAILED=0

echo "Total nodes to check: ${TOTAL_NODES}" >&2

# Check each node
for NODE in "${NODE_ARRAY[@]}"; do
  echo "Checking node: ${NODE}" >&2

  # Try to check if user exists
  if ssh ${SSH_OPTS} -i "${ADMIN_KEY}" "${ADMIN_USER}@${NODE}" "id ${TARGET_USERNAME}" 2>/dev/null >&2; then
    echo "  ✓ User exists on ${NODE}" >&2
    ((NODES_WITH_USER++))
    ((NODES_CHECKED++))
  else
    # Check if SSH connection itself failed
    if ssh ${SSH_OPTS} -i "${ADMIN_KEY}" "${ADMIN_USER}@${NODE}" "echo connected" 2>/dev/null >&2; then
      echo "  ✗ User does not exist on ${NODE}" >&2
      ((NODES_CHECKED++))
    else
      echo "  ⚠ SSH connection failed to ${NODE}" >&2
      ((SSH_FAILED++))
    fi
  fi
done

# If SSH failed to all nodes, we can't determine user state
if [ "$SSH_FAILED" -eq "$TOTAL_NODES" ]; then
  echo "ERROR: SSH connection failed to all nodes. Cannot check user existence." >&2
  echo "  Admin user: ${ADMIN_USER}" >&2
  echo "  Admin key: ${ADMIN_KEY}" >&2
  jq -n \
    --arg user_exists "false" \
    --arg checked_nodes "0" \
    --arg nodes_with_user "0" \
    --arg check_method "error" \
    --arg error "SSH connection failed to all $TOTAL_NODES nodes" \
    '{user_exists: $user_exists, checked_nodes: $checked_nodes, nodes_with_user: $nodes_with_user, check_method: $check_method, error: $error}'
  exit 0
fi

# Determine if user exists on all nodes
if [ "$NODES_WITH_USER" -eq "$NODES_CHECKED" ] && [ "$NODES_CHECKED" -gt 0 ]; then
  USER_EXISTS="true"
  echo "Result: User exists on all checked nodes (${NODES_WITH_USER}/${NODES_CHECKED})" >&2
elif [ "$NODES_WITH_USER" -eq 0 ]; then
  USER_EXISTS="false"
  echo "Result: User does not exist on any checked nodes" >&2
else
  # User exists on some but not all nodes - this is an error condition
  USER_EXISTS="partial"
  echo "Result: User exists on ${NODES_WITH_USER} of ${NODES_CHECKED} checked nodes (INCONSISTENT)" >&2
fi

# Output JSON result
jq -n \
  --arg user_exists "$USER_EXISTS" \
  --arg checked_nodes "$NODES_CHECKED" \
  --arg nodes_with_user "$NODES_WITH_USER" \
  --arg check_method "ssh" \
  '{user_exists: $user_exists, checked_nodes: $checked_nodes, nodes_with_user: $nodes_with_user, check_method: $check_method}'
