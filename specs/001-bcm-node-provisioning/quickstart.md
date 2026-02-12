# BCM Node Provisioning Module - Quick Start Guide

**Feature**: BCM Node Provisioning Module  
**Branch**: `001-bcm-node-provisioning`  
**Estimated Time**: 45 minutes (15 min setup + 30 min first provisioning)

---

## Prerequisites (15 minutes)

Before using this module, verify all BCM infrastructure prerequisites are met:

### 1. BCM Headnode Operational ✅
```bash
# SSH to BCM headnode
ssh admin@bcm-headnode

# Verify BCM services running
cmsh -c "cluster; get"
```

**Expected**: BCM 10 installed, cluster services active

---

### 2. Software Image Available ✅
```bash
# List available software images
cmsh -c "softwareimage; list"
```

**Expected Output**:
```
ubuntu-22.04-nvidia-535    /cm/images/ubuntu-22.04-nvidia-535
centos-7.9                 /cm/images/centos-7.9
```

**Action**: Note the exact image name (case-sensitive) for `software_image_name` variable.

---

### 3. Networks Configured ✅
```bash
# List networks
cmsh -c "network; list"
```

**Expected Output**:
```
dgxnet      10.184.162.0/24    (Management/PXE network)
oob-mgmt    10.229.10.0/24     (OOB/IPMI network)
```

**Action**: Verify management network has DHCP range configured.

---

### 4. Provisioning Services Active ✅
```bash
# Check provisioning configuration
cat /etc/cmd.conf | grep -E "(MaxNumberOfProvisioningThreads|DeviceResolveAnyMAC)"
```

**Expected Output**:
```
MaxNumberOfProvisioningThreads=10
DeviceResolveAnyMAC=1
```

**Action**: If not set, edit `/etc/cmd.conf` and restart `cmd` service.

---

### 5. BMC Connectivity Verified ✅
```bash
# Test IPMI access to target node BMC
ipmitool -I lanplus -H 10.229.10.50 -U admin -P <password> power status
```

**Expected Output**: `Chassis Power is off` or `Chassis Power is on`

**Action**: Verify all target node BMC IPs are reachable from headnode.

---

## Installation (5 minutes)

### Step 1: Clone Repository
```bash
git clone <repository-url>
cd bcm_kubespray_runai_gpu
git checkout -b feature/001-bcm-node-provisioning dev
```

---

### Step 2: Copy Module (or reference local path)
```bash
# Module will be at: ./bcm_node_provisioning/
ls -la bcm_node_provisioning/
```

**Expected Files**:
```
main.tf
data.tf
power.tf
variables.tf
outputs.tf
locals.tf
versions.tf
README.md
```

---

### Step 3: Configure Provider
Verify BCM provider credentials are set (should already exist in root `providers.tf`):

```bash
# Check provider configuration
cat providers.tf | grep -A5 "provider \"bcm\""
```

**Set credentials** via environment variables:
```bash
export BCM_ENDPOINT="https://bcm-headnode:8081"
export BCM_USERNAME="admin"
export BCM_PASSWORD="<your-password>"
```

---

## Configuration (10 minutes)

### Step 1: Create Root Module Configuration

Create `main.tf` in repository root (or append to existing):

```hcl
# main.tf (or dedicated file like node-provisioning.tf)

module "node_provisioning" {
  source = "./bcm_node_provisioning"
  
  # Node configurations
  nodes = {
    "dgx-05" = {
      mac       = "00:1A:2B:3C:4D:5E"  # Get from hardware label
      bmc_mac   = "00:1A:2B:3C:4D:5F"  # BMC interface MAC
      ipmi_ip   = "10.229.10.50"       # BMC IP on OOB network
      category  = "gpu-worker"
      roles     = ["compute", "gpu"]
    }
    "dgx-06" = {
      mac       = "00:11:22:33:44:55"
      bmc_mac   = "00:11:22:33:44:56"
      ipmi_ip   = "10.229.10.51"
      category  = "gpu-worker"
      roles     = ["compute", "gpu"]
    }
  }
  
  # Software image selection
  software_image_name = "ubuntu-22.04-nvidia-535"
  
  # Network configuration
  management_network = "dgxnet"
  oob_network        = "oob-mgmt"
  
  # BMC credentials (from environment variables)
  bmc_username = var.bmc_username
  bmc_password = var.bmc_password
  
  # Power actions disabled by default
  enable_power_action = false
}
```

---

### Step 2: Create Variables File

Create `terraform.tfvars`:

```hcl
# terraform.tfvars

# BCM Provider credentials (already configured in root)
# bcm_endpoint = "https://bcm-headnode:8081"
# bcm_username = "admin"
# bcm_password = "<from-environment>"

# BMC credentials (for IPMI power control)
bmc_username = "admin"
bmc_password = "<from-environment-or-vault>"
```

**Security Best Practice**: Use environment variables instead:
```bash
export TF_VAR_bmc_username="admin"
export TF_VAR_bmc_password="YourSecurePassword"
```

---

### Step 3: Add Variable Declarations

Add to `variables.tf` (if not using environment variables):

```hcl
variable "bmc_username" {
  description = "BMC/IPMI username for power control"
  type        = string
  sensitive   = true
}

variable "bmc_password" {
  description = "BMC/IPMI password for power control"
  type        = string
  sensitive   = true
}
```

---

## Initial Provisioning (30 minutes)

### Step 1: Initialize Terraform
```bash
terraform init
```

**Expected Output**: BCM provider installed, module initialized.

---

### Step 2: Create Device Records (No Power Actions)
```bash
terraform plan
terraform apply
```

**What Happens**:
- ✅ Data sources query software images and networks
- ✅ Device records created in BCM for dgx-05 and dgx-06
- ✅ Categories assigned
- ✅ Interfaces configured
- ❌ **No power actions** (nodes remain powered off)

**Duration**: 30-60 seconds

---

### Step 3: Trigger Initial Provisioning
```bash
terraform apply \
  -var="enable_power_action=true" \
  -var="power_action=power_on"
```

**What Happens**:
- 🔌 IPMI power_on commands sent to dgx-05 and dgx-06 BMCs
- 🌐 Nodes boot via PXE from management network
- 📦 Download OS image from BCM headnode via TFTP
- 💾 Install OS (partition disks, copy files, configure)
- ⚙️ Run post-install scripts
- ✅ Nodes boot into operational OS

**Duration**: 30 minutes per node (parallel mode: both provision simultaneously)

---

### Step 4: Monitor Provisioning Status

**Option 1: BCM Web UI**
- Navigate to Devices → Node List
- Watch provisioning status for dgx-05 and dgx-06

**Option 2: Command Line**
```bash
# On BCM headnode
cmsh -c "device; status dgx-05; status dgx-06"
```

**Option 3: Terraform Outputs**
```bash
# After provisioning completes (30 min)
terraform refresh
terraform output node_status
```

**Expected Output**:
```hcl
node_status = {
  "dgx-05" = {
    state    = "active"
    ip       = "10.184.162.109"
    success  = true
  }
  "dgx-06" = {
    state    = "active"
    ip       = "10.184.162.110"
    success  = true
  }
}
```

---

## Verification (5 minutes)

### Step 1: SSH to Provisioned Nodes
```bash
# SSH to first node
ssh root@10.184.162.109

# Verify OS version
cat /etc/os-release

# Verify GPU drivers (for GPU nodes)
nvidia-smi
```

**Expected**: Ubuntu 22.04 with NVIDIA driver 535 installed.

---

### Step 2: Check Node Registration in BCM
```bash
# On BCM headnode
cmsh -c "device; list"
```

**Expected Output**:
```
dgx-05    active    10.184.162.109    gpu-worker
dgx-06    active    10.184.162.110    gpu-worker
```

---

### Step 3: Verify Terraform State
```bash
terraform show | grep -A5 "bcm_cmdevice_device"
```

**Expected**: Device resources in state with correct hostnames and MACs.

---

## Common Issues & Troubleshooting

### Issue 1: Software Image Not Found
**Error**: `Software image 'ubuntu-22.04' not found`

**Solution**:
```bash
# List exact image names on BCM
cmsh -c "softwareimage; list"

# Update terraform.tfvars with exact name (case-sensitive)
software_image_name = "ubuntu-22.04-nvidia-535"
```

---

### Issue 2: BMC Unreachable
**Error**: `IPMI power action failed: BMC 10.229.10.50 unreachable`

**Solution**:
```bash
# Test connectivity from BCM headnode
ping 10.229.10.50

# Test IPMI authentication
ipmitool -I lanplus -H 10.229.10.50 -U admin -P <password> power status

# Check OOB network routing
ip route | grep 10.229.10.0
```

---

### Issue 3: Provisioning Stuck at "Provisioning" State
**Symptoms**: Node state remains "provisioning" for >60 minutes

**Solution**:
```bash
# Check provisioning logs on BCM headnode
tail -f /var/log/cmd/provisioning.log

# Check node console via IPMI SOL (Serial Over LAN)
ipmitool -I lanplus -H 10.229.10.50 -U admin -P <password> sol activate

# Common causes:
# - Network issues (check DHCP, TFTP logs)
# - Disk partitioning failure (check disksetup XML)
# - Image corruption (verify image checksum)
```

---

### Issue 4: Duplicate MAC Address
**Error**: `MAC address 00:1A:2B:3C:4D:5E already registered`

**Solution**:
```bash
# Find conflicting device
cmsh -c "device; list"

# Remove old device if it's a duplicate
cmsh -c "device use <old-hostname>; remove"

# Re-apply Terraform configuration
terraform apply
```

---

## Next Steps

### 1. Re-provision with New Image
```bash
# Update software image in main.tf
software_image_name = "ubuntu-22.04-nvidia-550"

# Apply configuration
terraform apply

# Trigger re-provisioning
terraform apply \
  -var="enable_power_action=true" \
  -var="power_action=power_cycle"
```

**Duration**: 30 minutes (nodes reboot and re-image)

---

### 2. Add More Nodes
```hcl
# Edit main.tf, add to nodes map
nodes = {
  # ... existing nodes ...
  "cpu-03" = {
    mac       = "AA:BB:CC:DD:EE:FF"
    bmc_mac   = "AA:BB:CC:DD:EE:00"
    ipmi_ip   = "10.229.10.30"
    category  = "control-plane"
    roles     = ["control_plane", "etcd"]
  }
}
```

```bash
terraform apply  # Create device record
terraform apply -var="enable_power_action=true" -var="power_action=power_on"
```

---

### 3. Scale to 10+ Nodes
For large-scale provisioning:

```hcl
# Set parallel provisioning mode
provisioning_mode = "parallel"
```

```bash
terraform apply -var="enable_power_action=true" -var="power_action=power_on"
```

**Duration**: 30-60 minutes for up to 10 nodes (BCM slot limit)

---

## Summary Checklist

- [x] BCM headnode operational with services active
- [x] Software images imported and verified
- [x] Networks configured with DHCP/TFTP/PXE
- [x] BMC connectivity tested from headnode
- [x] Module configured with correct node details
- [x] Device records created in BCM (terraform apply)
- [x] Initial provisioning triggered (enable_power_action=true)
- [x] Nodes provisioned successfully (status = "active")
- [x] SSH access verified to provisioned nodes
- [x] GPU drivers functional (for GPU nodes)

**You're Ready!** 🎉

---

## Additional Resources

- **BCM Documentation**: `/usr/share/doc/cmd/`
- **Module README**: `bcm_node_provisioning/README.md`
- **Data Model**: `specs/001-bcm-node-provisioning/data-model.md`
- **Research Findings**: `specs/001-bcm-node-provisioning/research.md`
- **Full Specification**: `specs/001-bcm-node-provisioning/spec.md`

---

## Support

**Issues**: Report via GitHub Issues or internal ticketing system  
**Questions**: Contact platform team or Terraform channel

**Module Version**: 1.0.0 (Beta)
