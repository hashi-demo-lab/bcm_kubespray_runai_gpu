#!/bin/bash
# =============================================================================
# Setup ansiblebcm User on BCM Nodes
# =============================================================================
# Run this script on each BCM node as root or with sudo to create the
# ansiblebcm service account for Ansible/Kubespray deployment.
#
# Usage:
#   sudo ./setup-ansiblebcm-user.sh "<SSH_PUBLIC_KEY>"
#
# Example:
#   sudo ./setup-ansiblebcm-user.sh "ssh-rsa AAAAB3NzaC1yc2EAAAADAQAB..."
# =============================================================================

set -e

# Configuration
USERNAME="ansiblebcm"
UID_NUM=60000
GID_NUM=60000
SHELL="/bin/bash"
HOME_DIR="/home/${USERNAME}"

# Get SSH public key from argument
SSH_PUBLIC_KEY="$1"

if [ -z "$SSH_PUBLIC_KEY" ]; then
    echo "ERROR: SSH public key required as argument"
    echo ""
    echo "Usage: sudo $0 \"<SSH_PUBLIC_KEY>\""
    echo ""
    echo "Get the key from Terraform:"
    echo "  terraform output ssh_public_key"
    echo "  # or"
    echo "  cat generated_ssh_key.pub"
    exit 1
fi

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root or with sudo"
    exit 1
fi

echo "=========================================="
echo "Setting up ${USERNAME} user"
echo "=========================================="
echo "UID: ${UID_NUM}"
echo "GID: ${GID_NUM}"
echo "Home: ${HOME_DIR}"
echo "=========================================="

# Create group if it doesn't exist
if getent group ${USERNAME} > /dev/null 2>&1; then
    echo "Group ${USERNAME} already exists"
else
    echo "Creating group ${USERNAME} with GID ${GID_NUM}..."
    groupadd -g ${GID_NUM} ${USERNAME}
    echo "Group created"
fi

# Create user if it doesn't exist
if id ${USERNAME} > /dev/null 2>&1; then
    echo "User ${USERNAME} already exists"
else
    echo "Creating user ${USERNAME} with UID ${UID_NUM}..."
    useradd -m -u ${UID_NUM} -g ${GID_NUM} -s ${SHELL} ${USERNAME}
    echo "User created"
fi

# Setup SSH directory
echo "Setting up SSH directory..."
mkdir -p ${HOME_DIR}/.ssh
chmod 700 ${HOME_DIR}/.ssh

# Add SSH public key
echo "Adding SSH public key..."
echo "${SSH_PUBLIC_KEY}" > ${HOME_DIR}/.ssh/authorized_keys
chmod 600 ${HOME_DIR}/.ssh/authorized_keys

# Set ownership
chown -R ${USERNAME}:${USERNAME} ${HOME_DIR}/.ssh

# Configure passwordless sudo
echo "Configuring passwordless sudo..."
echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME}
chmod 440 /etc/sudoers.d/${USERNAME}

# Validate sudoers file
if visudo -cf /etc/sudoers.d/${USERNAME} > /dev/null 2>&1; then
    echo "Sudoers configuration valid"
else
    echo "ERROR: Sudoers configuration invalid!"
    rm -f /etc/sudoers.d/${USERNAME}
    exit 1
fi

# Verify setup
echo ""
echo "=========================================="
echo "Verification"
echo "=========================================="
echo "User ID: $(id ${USERNAME})"
echo "SSH authorized_keys: $(ls -la ${HOME_DIR}/.ssh/authorized_keys)"
echo "Sudoers file: $(ls -la /etc/sudoers.d/${USERNAME})"
echo ""
echo "Setup completed successfully on $(hostname)"
echo "=========================================="
