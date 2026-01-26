#!/bin/bash
# =============================================================================
# Relocate Containerd Storage to a Larger Partition
# =============================================================================
# This script moves containerd's data directory to a partition with more space.
# Required when the default /var partition is too small for GPU Operator images.
#
# Usage:
#   ./relocate-containerd.sh <node> <target_path>
#
# Example:
#   ./relocate-containerd.sh dgx-05 /local
#   ./relocate-containerd.sh dgx-06 /local
#
# This will:
#   1. Stop containerd service
#   2. Create /local/containerd directory
#   3. Copy existing data from /var/lib/containerd
#   4. Create symlink: /var/lib/containerd -> /local/containerd
#   5. Restart containerd service
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
SSH_USER="${SSH_USER:-ibm}"
SSH_KEY="${SSH_KEY:-${PROJECT_DIR}/generated_ssh_key}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse arguments
NODE="$1"
TARGET_BASE="$2"

if [[ -z "$NODE" || -z "$TARGET_BASE" ]]; then
    echo "Usage: $0 <node> <target_path>"
    echo ""
    echo "Example:"
    echo "  $0 dgx-05 /local"
    echo ""
    exit 1
fi

TARGET_PATH="${TARGET_BASE}/containerd"

echo "=============================================="
echo "Relocate Containerd Storage"
echo "=============================================="
echo "Node: $NODE"
echo "Target: $TARGET_PATH"
echo "SSH User: $SSH_USER"
echo "=============================================="
echo ""

# SSH helper
ssh_cmd() {
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 \
        -o LogLevel=ERROR \
        ${SSH_KEY:+-i "$SSH_KEY"} \
        "${SSH_USER}@${NODE}" "$@"
}

# Check if already relocated
echo -n "Checking current containerd path... "
CURRENT_PATH=$(ssh_cmd "readlink -f /var/lib/containerd 2>/dev/null || echo /var/lib/containerd")

if [[ "$CURRENT_PATH" == "$TARGET_PATH" ]]; then
    echo -e "${GREEN}Already relocated to $TARGET_PATH${NC}"
    exit 0
fi

echo "$CURRENT_PATH"

# Check target partition space
echo -n "Checking target partition space... "
TARGET_AVAIL_KB=$(ssh_cmd "df '$TARGET_BASE' 2>/dev/null | tail -1 | awk '{print \$4}'" 2>/dev/null || echo "0")
TARGET_AVAIL_GB=$((TARGET_AVAIL_KB / 1024 / 1024))

if [[ $TARGET_AVAIL_GB -lt 10 ]]; then
    echo -e "${RED}FAILED${NC}"
    echo "Target partition $TARGET_BASE has only ${TARGET_AVAIL_GB}GB available"
    echo "Need at least 10GB for GPU Operator images"
    exit 1
fi
echo "${TARGET_AVAIL_GB}GB available"

# Confirm
echo ""
echo -e "${YELLOW}WARNING: This will stop containerd and may affect running containers${NC}"
read -p "Continue? [y/N] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Execute relocation
echo ""
echo "Relocating containerd..."
echo ""

ssh_cmd "sudo bash -s" << EOF
set -e

echo "[1/6] Stopping containerd..."
systemctl stop containerd

echo "[2/6] Creating target directory..."
mkdir -p ${TARGET_PATH}

echo "[3/6] Copying data (this may take a while)..."
rsync -av /var/lib/containerd/ ${TARGET_PATH}/

echo "[4/6] Backing up original directory..."
mv /var/lib/containerd /var/lib/containerd.old

echo "[5/6] Creating symlink..."
ln -s ${TARGET_PATH} /var/lib/containerd

echo "[6/6] Starting containerd..."
systemctl start containerd

echo ""
echo "Verifying..."
ls -la /var/lib/containerd
df -h ${TARGET_PATH}

echo ""
echo "Cleaning up old directory..."
rm -rf /var/lib/containerd.old

echo ""
echo "Done!"
EOF

echo ""
echo -e "${GREEN}Containerd relocated successfully on $NODE${NC}"
echo "New path: $TARGET_PATH"
