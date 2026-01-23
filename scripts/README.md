# BCM User Creation Script

## Overview

This directory contains the pre-deployment script required to create the `ansiblebcm` user on BCM-managed nodes before running Terraform.

**Why is this needed?**
The BCM Terraform provider (hashi-demo-lab/bcm) does not support user management resources (`bcm_cmuser_group`, `bcm_cmuser_user`). Therefore, the user must be created manually or via this script before Terraform deployment.

## Prerequisites

1. **SSH access** to all BCM nodes as an admin user (typically `root` or a user with passwordless sudo)
2. **Generated SSH key** from Terraform (used for passwordless authentication)
3. **Admin SSH private key** to access the nodes

## Usage

### Step 1: Generate SSH Key with Terraform

First, generate the SSH key that will be used for the `ansiblebcm` user:

```bash
terraform apply -target=tls_private_key.ssh_key -target=local_file.ssh_public_key
```

This creates `./ssh_key.pub` which will be deployed to the nodes.

### Step 2: Run User Creation Script

Run the script to create the user on all BCM nodes:

```bash
# Make script executable (if not already)
chmod +x scripts/create-user.sh

# Create user on nodes
./scripts/create-user.sh \
  --nodes node1,node2,node3 \
  --admin-user root \
  --admin-key ~/.ssh/id_rsa
```

**Script Options:**
- `--nodes <node1,node2,...>` - **Required**: Comma-separated list of node hostnames/IPs
- `--admin-user <user>` - Admin SSH user (default: `root`)
- `--admin-key <path>` - Path to admin SSH private key (default: `~/.ssh/id_rsa`)
- `--username <name>` - Username to create (default: `ansiblebcm`)
- `--uid <id>` - User ID (default: `60000`)
- `--gid <id>` - Group ID (default: `60000`)
- `--ssh-key <path>` - Path to SSH public key file (default: `./ssh_key.pub`)
- `--help` - Show help message

### Step 3: Run Terraform Deployment

After the user is created successfully on all nodes, proceed with Terraform:

```bash
terraform plan
terraform apply
```

## What the Script Does

The `create-user.sh` script performs the following on each BCM node:

1. **Creates group**: Creates the group with GID 60000 (default)
2. **Creates user**: Creates the user with UID 60000 (default)
3. **Sets up SSH**: Configures SSH authorized_keys for passwordless authentication
4. **Configures sudo**: Grants passwordless sudo access to the user
5. **Sets permissions**: Ensures proper ownership and permissions on all files

## Example Output

```
===================================================================
BCM User Creation Script
===================================================================
Nodes:        node1,node2,node3
Admin User:   root
Admin Key:    /root/.ssh/id_rsa
Username:     ansiblebcm
UID:          60000
GID:          60000
SSH Key:      ./ssh_key.pub
===================================================================

Processing node: node1
Creating group ansiblebcm with GID 60000...
Group ansiblebcm created with GID 60000
Creating user ansiblebcm with UID 60000...
User ansiblebcm created with UID 60000
Configuring SSH access...
SSH key configured for ansiblebcm
Configuring passwordless sudo...
Passwordless sudo configured for ansiblebcm
User ansiblebcm setup completed successfully
✓ Successfully created user ansiblebcm on node1

[... similar output for other nodes ...]

===================================================================
Summary
===================================================================
Total nodes:    3
Successful:     3
Failed:         0

✓ All nodes configured successfully!

You can now run Terraform:
  terraform plan
  terraform apply
===================================================================
```

## Troubleshooting

### SSH Connection Fails

If SSH connection fails to a node:
- Verify the admin user has SSH access to the node
- Check that the admin SSH key is correct and has proper permissions (600)
- Ensure the node is reachable on the network
- Verify the admin user has sudo privileges

### User Already Exists

If the user already exists with different UID/GID, the script will show a warning but continue. You may need to:
1. Manually delete the existing user on the node
2. Re-run the script

### Permission Denied

If you get "Permission denied" errors:
- Ensure the admin user has sudo privileges
- If using a non-root user, verify they have passwordless sudo configured

## Alternative: Manual User Creation

If you prefer to create the user manually, run these commands on each BCM node:

```bash
# Create group
sudo groupadd -g 60000 ansiblebcm

# Create user
sudo useradd -m -u 60000 -g 60000 -s /bin/bash ansiblebcm

# Set up SSH directory
sudo mkdir -p /home/ansiblebcm/.ssh
sudo chmod 700 /home/ansiblebcm/.ssh

# Add SSH public key (replace with your actual public key)
sudo bash -c 'echo "ssh-rsa AAAAB3..." > /home/ansiblebcm/.ssh/authorized_keys'
sudo chmod 600 /home/ansiblebcm/.ssh/authorized_keys
sudo chown -R ansiblebcm:ansiblebcm /home/ansiblebcm/.ssh

# Configure passwordless sudo
sudo bash -c 'echo "ansiblebcm ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansiblebcm'
sudo chmod 440 /etc/sudoers.d/ansiblebcm
```

## Files

- [`create-user.sh`](create-user.sh) - Main user creation script
- [`deploy-kubespray.sh`](deploy-kubespray.sh) - Kubespray deployment script (runs after user creation)
- [`fetch-kubeconfig.sh`](fetch-kubeconfig.sh) - Kubeconfig extraction script
