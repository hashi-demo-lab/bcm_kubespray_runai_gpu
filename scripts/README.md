# BCM Kubernetes Deployment Scripts

## Overview

This directory contains scripts for deploying and managing BCM-based Kubernetes clusters with GPU support.

## Script Categories

### User Management Scripts

| Script                | Description                                                          |
| --------------------- | -------------------------------------------------------------------- |
| `create-user.sh`      | Creates the `ansiblebcm` user on BCM-managed nodes                   |
| `deploy-kubespray.sh` | Deploys Kubernetes via Kubespray                                     |
| `fetch-kubeconfig.sh` | Extracts kubeconfig from the cluster                                 |
| `setup-kubeconfig.sh` | Configures KUBECONFIG in shell profile for persistent kubectl access |

### GPU Operator Scripts

| Script                          | Description                                    |
| ------------------------------- | ---------------------------------------------- |
| `check-gpu-operator-prereqs.sh` | Validates GPU node prerequisites               |
| `relocate-containerd.sh`        | Moves containerd storage to larger partition   |
| `setup-helm-nfs.sh`             | Configures Helm for NFS home directories       |
| `install-gpu-operator.sh`       | Full GPU Operator installation with pre-checks |

---

## GPU Operator Scripts

### check-gpu-operator-prereqs.sh

Validates that GPU nodes meet all requirements before GPU Operator installation.

**Checks performed:**

- SSH connectivity to all GPU nodes
- NVIDIA driver presence (for determining driver.enabled setting)
- Containerd storage space (minimum 10GB)
- Kernel headers availability
- NFS home directory detection (Helm compatibility)
- KUBECONFIG access

**Usage:**

```bash
# Copy to control plane and run
scp scripts/check-gpu-operator-prereqs.sh ibm@cpu-03:~/
ssh ibm@cpu-03 "chmod +x ~/check-gpu-operator-prereqs.sh && ~/check-gpu-operator-prereqs.sh"
```

### relocate-containerd.sh

Moves containerd storage from `/var/lib/containerd` to a larger partition.

**Why needed:** DGX nodes often have small `/var` partitions (~6GB) insufficient for NVIDIA driver images (~3GB).

**Usage:**

```bash
./relocate-containerd.sh <node> <target-partition>
./relocate-containerd.sh dgx-05 /local
./relocate-containerd.sh dgx-06 /local
```

**What it does:**

1. Stops containerd
2. Creates target directory
3. Syncs existing data
4. Creates symlink
5. Restarts containerd
6. Cleans up old data

### setup-helm-nfs.sh

Configures Helm environment variables for NFS-mounted home directories.

**Why needed:** Helm uses file locking which fails on NFS filesystems.

**Usage:**

```bash
source ./setup-helm-nfs.sh
```

**Environment variables set:**

```bash
export HELM_CACHE_HOME=/tmp/helm-cache
export HELM_CONFIG_HOME=/tmp/helm-config
export HELM_DATA_HOME=/tmp/helm-data
```

### install-gpu-operator.sh

Full GPU Operator installation with integrated prerequisite checks.

**Usage:**

```bash
./install-gpu-operator.sh [--skip-prereqs] [--driver-enabled true|false]
```

---

## User Management Scripts

### create-user.sh

Creates the `ansiblebcm` user on BCM-managed nodes.

**Note:** This is typically handled automatically by Terraform. Use this script only for manual deployments.

### setup-kubeconfig.sh

Configures the KUBECONFIG environment variable in your shell profile for persistent kubectl access across SSH sessions.

**Why needed:** After cluster deployment, kubectl requires the kubeconfig file. Without setting KUBECONFIG persistently, you must specify `--kubeconfig` on every command or set it manually each SSH session.

**Usage:**

```bash
./scripts/setup-kubeconfig.sh
source ~/.bashrc
```

**What it does:**

1. Detects the kubeconfig file location in the repo
2. Adds `export KUBECONFIG=...` to your shell config (~/.bashrc, ~/.bash_profile, or ~/.zshrc)
3. Tests kubectl connectivity

**Run after:** Initial cluster deployment via Terraform

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
