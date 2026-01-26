# GPU Operator Prerequisites

This document outlines the prerequisites and assumptions for deploying the NVIDIA GPU Operator on BCM-managed Kubernetes clusters.

## Terraform Automation

**GPU Node Preparation is now automated via Terraform.** The `gpu_node_preparation.tf` file:

1. **Validates prerequisites** - Checks disk space, SSH connectivity, and containerd status
2. **Labels GPU nodes** - Applies `nvidia.com/gpu.present=true` and other required labels
3. **Fails early** - Stops deployment if prerequisites are not met

### Configuration Variables

```hcl
# In your .tfvars file:
gpu_worker_nodes             = ["dgx-05", "dgx-06"]
enable_gpu_node_labels       = true
enable_gpu_prereq_validation = true
min_containerd_space_gb      = 10
```

### What Gets Checked Automatically

When `enable_gpu_prereq_validation = true`, Terraform validates:
- ✅ SSH connectivity to all GPU nodes
- ✅ Containerd service is running
- ✅ Sufficient disk space for containerd (minimum 10GB)

**If validation fails, Terraform will stop** and display an error message with remediation steps.

---

## Manual Prerequisites (Before Terraform)

The following must be done **manually before running Terraform**:

### Containerd Storage Relocation

If GPU nodes have insufficient disk space on `/var` (< 10GB available), relocate containerd:

```bash
./scripts/relocate-containerd.sh dgx-05 /local
./scripts/relocate-containerd.sh dgx-06 /local
```

This is a **one-time manual step** that cannot be safely automated.

---

## Deployment Location

**IMPORTANT**: All scripts in this document should be run on the **Kubernetes control plane node** (e.g., `cpu-03`), not on your local machine.

### Option 1: Copy scripts to control plane
```bash
# From your local machine
scp -r scripts/ ibm@cpu-03:~/gpu-operator-scripts/
ssh ibm@cpu-03 "chmod +x ~/gpu-operator-scripts/*.sh"

# Then SSH to control plane and run
ssh ibm@cpu-03
cd ~/gpu-operator-scripts
./check-gpu-operator-prereqs.sh
```

### Option 2: Run commands directly via SSH
```bash
# From your local machine, run commands on control plane
ssh ibm@cpu-03 "bash -s" < scripts/check-gpu-operator-prereqs.sh
```

## Overview

The NVIDIA GPU Operator automates the management of NVIDIA software components needed to provision GPU nodes in Kubernetes. Before installation, certain requirements must be met on both the control plane and GPU worker nodes.

## Issues Encountered During Deployment

The following issues were discovered during deployment and are now codified as pre-requisite checks:

### 1. Helm File Locking on NFS Filesystems

**Problem**: Helm uses file locking for concurrent access protection. When the user's home directory is mounted via NFS (common in HPC environments), Helm fails with:
```
Error: no locks available
```

**Root Cause**: NFS filesystems don't support POSIX file locking by default.

**Solution**: Configure Helm to use a local filesystem path:
```bash
export HELM_CACHE_HOME=/tmp/helm-cache
export HELM_CONFIG_HOME=/tmp/helm-config
export HELM_DATA_HOME=/tmp/helm-data
```

**Pre-requisite Check**: Verify if home directory is NFS-mounted and configure Helm accordingly.

---

### 2. KUBECONFIG Access Permissions

**Problem**: Non-root users cannot access `/etc/kubernetes/admin.conf` which is required for kubectl/helm commands.

**Solution**: Either:
- Run commands with sudo and pass KUBECONFIG environment variable
- Copy admin.conf to user's home and set proper permissions

**Example**:
```bash
sudo KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes
```

---

### 3. NVIDIA Drivers Not Pre-installed on DGX Nodes

**Problem**: BCM-provisioned DGX nodes may not have NVIDIA drivers pre-installed. The GPU Operator was initially configured with `driver.enabled=false` assuming pre-installed drivers.

**Symptoms**:
- `nvidia-smi` command not found
- No nvidia kernel modules loaded (`lsmod | grep nvidia` returns empty)
- Driver validation pods fail with "failed to validate the driver"

**Solution**: Install GPU Operator with `driver.enabled=true`:
```bash
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --set driver.enabled=true \
  --set toolkit.enabled=true \
  --set devicePlugin.enabled=true
```

**Pre-requisite Check**: SSH to GPU nodes and verify if NVIDIA drivers are installed.

---

### 4. Insufficient Disk Space for Container Images

**Problem**: The NVIDIA driver container image is ~3GB. The default `/var` partition on BCM nodes is only 6GB, which is insufficient.

**Error**:
```
Failed to pull image "nvcr.io/nvidia/driver:580.105.08-ubuntu22.04":
no space left on device
```

**Solution**: Move containerd storage to a larger partition (e.g., `/local`):
```bash
systemctl stop containerd
mkdir -p /local/containerd
rsync -av /var/lib/containerd/ /local/containerd/
mv /var/lib/containerd /var/lib/containerd.old
ln -s /local/containerd /var/lib/containerd
systemctl start containerd
rm -rf /var/lib/containerd.old
```

**Pre-requisite Check**: Verify GPU nodes have at least 10GB available for containerd storage.

---

## Minimum Requirements Summary

| Requirement | Minimum | Recommended | Notes |
|-------------|---------|-------------|-------|
| Containerd Storage | 5GB | 10GB+ | For NVIDIA driver + toolkit images |
| Kernel Headers | Installed | - | Required if driver.enabled=true |
| SSH Access | Yes | - | For pre-req checks |
| kubectl/helm | Installed | - | On control plane node |

## Pre-requisite Check Script

Run the pre-requisite check script before installing the GPU Operator:

```bash
./scripts/check-gpu-operator-prereqs.sh
```

The script will:
1. Verify SSH connectivity to all GPU worker nodes
2. Check if NVIDIA drivers are pre-installed
3. Verify disk space availability for containerd
4. Check if home directory is NFS-mounted (Helm compatibility)
5. Verify KUBECONFIG access

If any check fails, the script provides remediation steps.

## Remediation Scripts

### Move Containerd to Larger Partition

```bash
./scripts/relocate-containerd.sh dgx-05 /local
./scripts/relocate-containerd.sh dgx-06 /local
```

### Configure Helm for NFS Environment

```bash
source ./scripts/setup-helm-nfs.sh
```

## Node Labels

GPU worker nodes should be labeled for the GPU Operator to target them:

```bash
kubectl label nodes dgx-05 dgx-06 nvidia.com/gpu.present=true
```

## Installation Command

After all pre-requisites pass:

```bash
# Source Helm NFS workaround if needed
source ./scripts/setup-helm-nfs.sh

# Install GPU Operator
sudo KUBECONFIG=/etc/kubernetes/admin.conf \
     HELM_CACHE_HOME=${HELM_CACHE_HOME:-$HOME/.cache/helm} \
     HELM_CONFIG_HOME=${HELM_CONFIG_HOME:-$HOME/.config/helm} \
     HELM_DATA_HOME=${HELM_DATA_HOME:-$HOME/.local/share/helm} \
     helm install gpu-operator nvidia/gpu-operator \
     --namespace gpu-operator \
     --create-namespace \
     --set driver.enabled=true \
     --set toolkit.enabled=true \
     --set devicePlugin.enabled=true \
     --set mig.strategy=single \
     --wait --timeout 15m
```

## Troubleshooting

### Check GPU Operator Pod Status
```bash
kubectl get pods -n gpu-operator
```

### Check Driver Pod Logs
```bash
kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset -c nvidia-driver-ctr
```

### Verify GPU Detection
```bash
kubectl describe nodes | grep -A5 "Capacity:" | grep nvidia
```

### Manual Driver Validation
```bash
ssh dgx-05 "nvidia-smi"
```
