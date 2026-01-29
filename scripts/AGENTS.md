# Scripts - Agent Guide

## Overview

All scripts support BCM-based bare metal Kubernetes deployment. Most scripts are designed to run **on the control plane node** (cpu-03), not locally.

## Script Inventory

### User Management

| Script | Runs On | Purpose |
|--------|---------|---------|
| `create-user.sh` | Local -> nodes via SSH | Creates `ansiblebcm` user (UID 60000) with SSH keys and passwordless sudo |
| `check-user-exists.sh` | Local -> nodes via SSH | Validates ansiblebcm user exists on all nodes |
| `deploy-user-to-all-nodes.sh` | Local | Wrapper to deploy user across all cluster nodes |
| `setup-ansiblebcm-user.sh` | Head node | Sets up ansiblebcm from the BCM head node |
| `setup-nodes-from-head.sh` | Head node | Bulk node configuration from head node |

### Kubernetes Deployment

| Script | Runs On | Purpose |
|--------|---------|---------|
| `deploy-kubespray.sh` | Control plane (cpu-03) | Executes Kubespray playbooks to deploy K8s |
| `fetch-kubeconfig.sh` | Control plane | Extracts kubeconfig from deployed cluster |
| `kubespray.conf.example` | N/A | Example Kubespray configuration template |

### GPU Operator

| Script | Runs On | Purpose |
|--------|---------|---------|
| `check-gpu-operator-prereqs.sh` | Control plane | Validates GPU nodes: SSH, drivers, disk space, kernel headers, NFS, KUBECONFIG |
| `relocate-containerd.sh <node> <partition>` | Control plane -> GPU nodes | Moves containerd storage from `/var` to larger partition (e.g., `/local`) |
| `setup-helm-nfs.sh` | Control plane | Sets HELM_*_HOME to `/tmp/helm-*` to avoid NFS file locking failures |
| `install-gpu-operator.sh` | Control plane | Full GPU Operator install with integrated prereq checks |

## Execution Context

### Running from local machine
```bash
# Copy scripts to control plane first
scp -r scripts/ ibm@cpu-03:~/scripts/
ssh ibm@cpu-03 "chmod +x ~/scripts/*.sh"
```

### Running on control plane
```bash
ssh ibm@cpu-03
cd ~/scripts/
./check-gpu-operator-prereqs.sh
```

### Running via SSH pipe
```bash
ssh ibm@cpu-03 "bash -s" < scripts/check-gpu-operator-prereqs.sh
```

## Common Failure Modes

### SSH connection failures
- Nodes may reset SSH keys on reboot (BCM-provisioned)
- Admin user `ibm` uses password auth (via `sshpass`), not key auth
- The `ansiblebcm` user uses key auth once created

### Containerd disk space
- DGX `/var` partitions are ~6GB, GPU driver images need ~3GB
- Must run `relocate-containerd.sh` before GPU Operator install
- This is a **one-time manual step** that cannot be safely automated
- Target partition is typically `/local` on DGX nodes

### Helm NFS locking
- Control plane nodes have NFS-mounted home directories
- Helm file locking fails on NFS
- Always `source setup-helm-nfs.sh` before running Helm commands

### KUBECONFIG access
- `/etc/kubernetes/admin.conf` is root-owned
- Non-root users need: `sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl ...`
- Or copy to user home: `sudo cp /etc/kubernetes/admin.conf ~/.kube/config`

## Script Dependencies

```
create-user.sh (or user_creation.tf)
  └── deploy-kubespray.sh (or ansible.tf)
       └── fetch-kubeconfig.sh (or kubeconfig.tf)
            └── check-gpu-operator-prereqs.sh
                 ├── relocate-containerd.sh (if needed)
                 └── setup-helm-nfs.sh (if NFS detected)
                      └── install-gpu-operator.sh (or gpu-operator.tf)
```

Note: Most of these scripts have Terraform equivalents in the root module. The scripts exist for manual deployment or debugging scenarios.
