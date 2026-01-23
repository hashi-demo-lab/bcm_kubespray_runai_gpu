#!/usr/bin/env bash
# =============================================================================
# BCM User Creation Script
# =============================================================================
# Creates the ansiblebcm user on BCM-managed nodes before Terraform deployment
#
# This script is required because the BCM Terraform provider does not support
# user management resources (bcm_cmuser_group, bcm_cmuser_user).
#
# Usage:
#   ./scripts/create-user.sh [OPTIONS]
#
# Options:
#   --nodes <node1,node2,...>  Comma-separated list of node hostnames/IPs
#   --admin-user <user>        Admin SSH user (default: root)
#   --admin-key <path>         Path to admin SSH private key (default: ~/.ssh/id_rsa)
#   --username <name>          Username to create (default: ansiblebcm)
#   --uid <id>                 User ID (default: 60000)
#   --gid <id>                 Group ID (default: 60000)
#   --ssh-key <path>           Path to SSH public key file (default: ./ssh_key.pub)
#   --help                     Show this help message
#
# Prerequisites:
#   - SSH access to BCM nodes as admin user (root or sudo user)
#   - Admin user must have passwordless sudo or be root
#   - Generated SSH key at ./ssh_key.pub (from Terraform)
#
# Example:
#   # Generate SSH key first with Terraform
#   terraform apply -target=tls_private_key.ssh_key -target=local_sensitive_file.ssh_private_key -target=local_file.ssh_public_key
#
#   # Then create user on nodes
#   ./scripts/create-user.sh --nodes node1,node2,node3 --admin-user root
#
# =============================================================================

set -euo pipefail

# Default values
NODES=""
ADMIN_USER="root"
ADMIN_KEY="${HOME}/.ssh/id_rsa"
USERNAME="ansiblebcm"
UID=60000
GID=60000
SSH_KEY_FILE="./ssh_key.pub"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --nodes)
      NODES="$2"
      shift 2
      ;;
    --admin-user)
      ADMIN_USER="$2"
      shift 2
      ;;
    --admin-key)
      ADMIN_KEY="$2"
      shift 2
      ;;
    --username)
      USERNAME="$2"
      shift 2
      ;;
    --uid)
      UID="$2"
      shift 2
      ;;
    --gid)
      GID="$2"
      shift 2
      ;;
    --ssh-key)
      SSH_KEY_FILE="$2"
      shift 2
      ;;
    --help)
      grep "^#" "$0" | grep -v "#!/" | sed 's/^# //' | sed 's/^#//'
      exit 0
      ;;
    *)
      echo -e "${RED}ERROR: Unknown option: $1${NC}"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [[ -z "$NODES" ]]; then
  echo -e "${RED}ERROR: --nodes is required${NC}"
  echo "Use --help for usage information"
  exit 1
fi

# Validate SSH key file exists
if [[ ! -f "$SSH_KEY_FILE" ]]; then
  echo -e "${RED}ERROR: SSH public key file not found: $SSH_KEY_FILE${NC}"
  echo ""
  echo "Generate the SSH key first with Terraform:"
  echo "  terraform apply -target=tls_private_key.ssh_key -target=local_file.ssh_public_key"
  exit 1
fi

# Read SSH public key
SSH_PUBLIC_KEY=$(cat "$SSH_KEY_FILE")

# SSH options for legacy BCM nodes
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o HostKeyAlgorithms=+ssh-rsa,ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa -o ConnectTimeout=10"

echo "==================================================================="
echo "BCM User Creation Script"
echo "==================================================================="
echo "Nodes:        ${NODES}"
echo "Admin User:   ${ADMIN_USER}"
echo "Admin Key:    ${ADMIN_KEY}"
echo "Username:     ${USERNAME}"
echo "UID:          ${UID}"
echo "GID:          ${GID}"
echo "SSH Key:      ${SSH_KEY_FILE}"
echo "==================================================================="
echo ""

# Convert comma-separated nodes to array
IFS=',' read -ra NODE_ARRAY <<< "$NODES"

FAILED_NODES=()
SUCCESS_COUNT=0

# Process each node
for NODE in "${NODE_ARRAY[@]}"; do
  echo -e "${YELLOW}Processing node: ${NODE}${NC}"

  # Create user creation script
  USER_SCRIPT=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -e

USERNAME="__USERNAME__"
UID=__UID__
GID=__GID__
SSH_PUBLIC_KEY="__SSH_PUBLIC_KEY__"

echo "Creating group ${USERNAME} with GID ${GID}..."
if getent group ${GID} >/dev/null 2>&1; then
  echo "Group with GID ${GID} already exists"
  EXISTING_GROUP=$(getent group ${GID} | cut -d: -f1)
  if [[ "$EXISTING_GROUP" != "$USERNAME" ]]; then
    echo "WARNING: GID ${GID} is used by group ${EXISTING_GROUP}, not ${USERNAME}"
  fi
else
  groupadd -g ${GID} ${USERNAME}
  echo "Group ${USERNAME} created with GID ${GID}"
fi

echo "Creating user ${USERNAME} with UID ${UID}..."
if id ${USERNAME} >/dev/null 2>&1; then
  echo "User ${USERNAME} already exists"
  EXISTING_UID=$(id -u ${USERNAME})
  EXISTING_GID=$(id -g ${USERNAME})
  if [[ "$EXISTING_UID" != "$UID" ]] || [[ "$EXISTING_GID" != "$GID" ]]; then
    echo "WARNING: User ${USERNAME} exists but with different UID/GID (UID: ${EXISTING_UID}, GID: ${EXISTING_GID})"
  fi
else
  useradd -m -u ${UID} -g ${GID} -s /bin/bash ${USERNAME}
  echo "User ${USERNAME} created with UID ${UID}"
fi

echo "Configuring SSH access..."
mkdir -p /home/${USERNAME}/.ssh
chmod 700 /home/${USERNAME}/.ssh
echo "${SSH_PUBLIC_KEY}" > /home/${USERNAME}/.ssh/authorized_keys
chmod 600 /home/${USERNAME}/.ssh/authorized_keys
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.ssh
echo "SSH key configured for ${USERNAME}"

echo "Configuring passwordless sudo..."
if [[ ! -f /etc/sudoers.d/${USERNAME} ]]; then
  echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME}
  chmod 440 /etc/sudoers.d/${USERNAME}
  echo "Passwordless sudo configured for ${USERNAME}"
else
  echo "Sudoers file already exists for ${USERNAME}"
fi

echo "User ${USERNAME} setup completed successfully"
EOFSCRIPT
)

  # Replace placeholders in script
  USER_SCRIPT="${USER_SCRIPT//__USERNAME__/$USERNAME}"
  USER_SCRIPT="${USER_SCRIPT//__UID__/$UID}"
  USER_SCRIPT="${USER_SCRIPT//__GID__/$GID}"
  USER_SCRIPT="${USER_SCRIPT//__SSH_PUBLIC_KEY__/$SSH_PUBLIC_KEY}"

  # Execute user creation script on remote node
  if ssh ${SSH_OPTS} -i "${ADMIN_KEY}" "${ADMIN_USER}@${NODE}" "sudo bash -s" <<< "$USER_SCRIPT" 2>&1; then
    echo -e "${GREEN}✓ Successfully created user ${USERNAME} on ${NODE}${NC}"
    ((SUCCESS_COUNT++))
  else
    echo -e "${RED}✗ Failed to create user ${USERNAME} on ${NODE}${NC}"
    FAILED_NODES+=("${NODE}")
  fi

  echo ""
done

# Summary
echo "==================================================================="
echo "Summary"
echo "==================================================================="
echo "Total nodes:    ${#NODE_ARRAY[@]}"
echo "Successful:     ${SUCCESS_COUNT}"
echo "Failed:         ${#FAILED_NODES[@]}"

if [[ ${#FAILED_NODES[@]} -gt 0 ]]; then
  echo ""
  echo -e "${RED}Failed nodes:${NC}"
  for NODE in "${FAILED_NODES[@]}"; do
    echo "  - ${NODE}"
  done
  echo ""
  exit 1
fi

echo ""
echo -e "${GREEN}✓ All nodes configured successfully!${NC}"
echo ""
echo "You can now run Terraform:"
echo "  terraform plan"
echo "  terraform apply"
echo "==================================================================="
