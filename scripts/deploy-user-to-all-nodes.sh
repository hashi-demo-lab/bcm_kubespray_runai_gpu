#!/bin/bash
# =============================================================================
# Deploy ansiblebcm User to All BCM Nodes
# =============================================================================
# Copies and runs the setup script on all BCM nodes using password auth.
#
# Usage:
#   ./deploy-user-to-all-nodes.sh
#
# Prerequisites:
#   - sshpass installed
#   - generated_ssh_key.pub exists (run: terraform apply -target=tls_private_key.ssh_key)
#   - IBM_PASSWORD environment variable set, or will prompt
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Node configuration - update these if needed
NODES="10.184.162.102 10.184.162.104 10.184.162.121 10.184.162.109 10.184.162.110"
ADMIN_USER="ibm"

# Get SSH public key
SSH_KEY_FILE="${PROJECT_DIR}/generated_ssh_key.pub"
if [ ! -f "$SSH_KEY_FILE" ]; then
    echo "ERROR: SSH public key file not found: $SSH_KEY_FILE"
    echo ""
    echo "Generate it first with:"
    echo "  terraform apply -target=tls_private_key.ssh_key -target=local_file.ssh_public_key"
    exit 1
fi

SSH_PUBLIC_KEY=$(cat "$SSH_KEY_FILE" | tr -d '\n')

# Check for sshpass
if ! command -v sshpass &> /dev/null; then
    echo "ERROR: sshpass not found. Install it with:"
    echo "  apt-get install sshpass  # Debian/Ubuntu"
    echo "  yum install sshpass      # RHEL/CentOS"
    exit 1
fi

# Get password
if [ -z "$IBM_PASSWORD" ]; then
    echo -n "Enter password for ${ADMIN_USER}: "
    read -s IBM_PASSWORD
    echo ""
fi

if [ -z "$IBM_PASSWORD" ]; then
    echo "ERROR: Password required"
    exit 1
fi

SETUP_SCRIPT="${SCRIPT_DIR}/setup-ansiblebcm-user.sh"
if [ ! -f "$SETUP_SCRIPT" ]; then
    echo "ERROR: Setup script not found: $SETUP_SCRIPT"
    exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

echo "=========================================="
echo "Deploying ansiblebcm user to all nodes"
echo "=========================================="
echo "Nodes: $NODES"
echo "Admin user: $ADMIN_USER"
echo "=========================================="
echo ""

SUCCESS=0
FAILED=0

for NODE in $NODES; do
    echo "----------------------------------------"
    echo "Processing node: $NODE"
    echo "----------------------------------------"

    # Copy setup script to node
    echo "Copying setup script..."
    if ! sshpass -p "$IBM_PASSWORD" scp $SSH_OPTS "$SETUP_SCRIPT" "${ADMIN_USER}@${NODE}:/tmp/setup-ansiblebcm-user.sh" 2>/dev/null; then
        echo "ERROR: Failed to copy script to $NODE"
        ((FAILED++))
        continue
    fi

    # Run setup script on node
    echo "Running setup script..."
    if sshpass -p "$IBM_PASSWORD" ssh $SSH_OPTS "${ADMIN_USER}@${NODE}" "sudo bash /tmp/setup-ansiblebcm-user.sh '${SSH_PUBLIC_KEY}' && rm -f /tmp/setup-ansiblebcm-user.sh" 2>&1; then
        echo "SUCCESS: Node $NODE configured"
        ((SUCCESS++))
    else
        echo "ERROR: Failed to run setup on $NODE"
        ((FAILED++))
    fi
    echo ""
done

echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Successful: $SUCCESS"
echo "Failed: $FAILED"
echo "=========================================="

if [ $FAILED -gt 0 ]; then
    echo ""
    echo "Some nodes failed. Check the output above for errors."
    exit 1
fi

echo ""
echo "All nodes configured! You can now run:"
echo "  terraform apply"
