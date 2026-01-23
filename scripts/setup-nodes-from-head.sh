#!/bin/bash
# =============================================================================
# Setup ansiblebcm User on All BCM Nodes (Run from Head Node)
# =============================================================================
# Run this script from the head node as the ibm user.
# It will SSH to each node and create the ansiblebcm user.
#
# Usage:
#   ./setup-nodes-from-head.sh "<SSH_PUBLIC_KEY>"
#
# Example:
#   ./setup-nodes-from-head.sh "ssh-rsa AAAAB3NzaC1yc2EAAAADAQAB..."
# =============================================================================

# Don't exit on error - we want to try all nodes
set +e

# Target nodes (using IP addresses for reliability)
declare -A NODES=(
    ["cpu-03"]="10.184.162.102"
    ["cpu-05"]="10.184.162.104"
    ["cpu-06"]="10.184.162.121"
    ["dgx-05"]="10.184.162.109"
    ["dgx-06"]="10.184.162.110"
)

# User configuration
USERNAME="ansiblebcm"
UID_NUM=60000
GID_NUM=60000

# Get SSH public key from argument
SSH_PUBLIC_KEY="$1"

if [ -z "$SSH_PUBLIC_KEY" ]; then
    echo "ERROR: SSH public key required as argument"
    echo ""
    echo "Usage: $0 \"<SSH_PUBLIC_KEY>\""
    echo ""
    echo "Get the key from the Terraform machine:"
    echo "  cat generated_ssh_key.pub"
    exit 1
fi

echo "=========================================="
echo "Setting up ${USERNAME} user on all nodes"
echo "=========================================="
echo "Nodes: ${!NODES[*]}"
echo "UID/GID: ${UID_NUM}"
echo "=========================================="
echo ""

SUCCESS=0
FAILED=0

for NODE_NAME in "${!NODES[@]}"; do
    NODE_IP="${NODES[$NODE_NAME]}"
    echo "----------------------------------------"
    echo "Configuring: $NODE_NAME ($NODE_IP)"
    echo "----------------------------------------"

    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "$NODE_IP" "sudo bash -s" 2>&1 << REMOTE_SCRIPT
set -e

# Create group if needed
if ! getent group ${USERNAME} > /dev/null 2>&1; then
    groupadd -g ${GID_NUM} ${USERNAME}
    echo "Created group ${USERNAME}"
else
    echo "Group ${USERNAME} exists"
fi

# Create user if needed
if ! id ${USERNAME} > /dev/null 2>&1; then
    useradd -m -u ${UID_NUM} -g ${GID_NUM} -s /bin/bash ${USERNAME}
    echo "Created user ${USERNAME}"
else
    echo "User ${USERNAME} exists"
fi

# Setup SSH
mkdir -p /home/${USERNAME}/.ssh
chmod 700 /home/${USERNAME}/.ssh
echo '${SSH_PUBLIC_KEY}' > /home/${USERNAME}/.ssh/authorized_keys
chmod 600 /home/${USERNAME}/.ssh/authorized_keys
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.ssh
echo "SSH key configured"

# Setup passwordless sudo
echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME}
chmod 440 /etc/sudoers.d/${USERNAME}
echo "Sudo configured"

# Verify
id ${USERNAME}
echo "Node configured successfully"
REMOTE_SCRIPT
    then
        echo "SUCCESS: $NODE_NAME ($NODE_IP)"
        ((SUCCESS++))
    else
        echo "FAILED: $NODE_NAME ($NODE_IP)"
        ((FAILED++))
    fi
    echo ""
done

TOTAL=${#NODES[@]}
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Successful: $SUCCESS / $TOTAL"
echo "Failed: $FAILED"
echo "=========================================="

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All nodes configured!"
