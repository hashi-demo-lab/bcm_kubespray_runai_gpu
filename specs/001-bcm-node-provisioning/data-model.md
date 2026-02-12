# Data Model: BCM Node Provisioning Module

**Feature**: BCM Node Provisioning Module  
**Branch**: `001-bcm-node-provisioning`  
**Date**: 2025-01-10

---

## Overview

This document defines the data model and entity relationships for the BCM Node Provisioning Terraform module. The model describes how nodes, categories, software images, networks, and power actions relate to each other in the provisioning workflow.

---

## Entity Relationship Diagram

```
┌─────────────────────┐
│  Software Image     │
│  (Pre-existing)     │
│────────────────────│
│ + uuid (PK)         │         ┌─────────────────────┐
│ + name              │◄────────│  Category           │
│ + path              │  refs   │  (Optional Create)  │
│ + kernel_params     │         │─────────────────────│
└─────────────────────┘         │ + name (PK)         │
                                │ + software_image    │────┐
┌─────────────────────┐         │   _proxy (UUID FK)  │    │
│  Network            │         │ + install_mode      │    │
│  (Pre-existing)     │         │ + bmc_settings      │    │
│─────────────────────│         │ + disksetup (XML)   │    │
│ + id (PK)           │         │ + initialize_script │    │
│ + name              │         │ + finalize_script   │    │
│ + cidr              │         │ + kernel_parameters │    │
└────────┬────────────┘         │ + boot_loader       │    │
         │                      └──────────┬──────────┘    │
         │ refs                            │ refs          │
         │                                 │               │
         │                      ┌──────────▼──────────┐    │
         │                      │  Device (Node)      │    │
         │                      │─────────────────────│    │
         └─────────────────────►│ + hostname (PK)     │    │
                  mgmt_network  │ + mac (unique)      │    │
                                │ + category (FK)     │◄───┘
         ┌───────────────────┐  │ + mgmt_network (FK) │
         │ interfaces[]      │◄─│ + power_control     │
         │───────────────────│  │ + bmc_settings {}   │
         │ + type            │  │ + interfaces []     │
         │ + name            │  │ + roles []          │
         │ + mac             │  │ + kernel_parameters │
         │ + network (FK)    │  │ + boot_loader       │
         │ + ip              │  └──────────┬──────────┘
         │ + bootable (bool) │             │
         └───────────────────┘             │ triggers
                                           │
                                ┌──────────▼──────────┐
                                │  Power Action       │
                                │  (Ephemeral)        │
                                │─────────────────────│
                                │ + device_id (FK)    │
                                │ + power_action      │
                                │   (enum)            │
                                │ + wait_for_         │
                                │   completion        │
                                │ + timeout           │
                                └──────────┬──────────┘
                                           │
                                           │ produces
                                           │
                                ┌──────────▼──────────┐
                                │  Node Status        │
                                │  (Queried)          │
                                │─────────────────────│
                                │ + hostname          │
                                │ + state (enum)      │
                                │ + ip                │
                                │ + mac               │
                                │ + roles []          │
                                └─────────────────────┘
```

---

## Core Entities

### 1. Node (Device)

Represents a bare metal server (DGX GPU worker or CPU control plane node) being provisioned.

**Attributes**:
- `hostname` (string, primary key) - Unique node identifier (e.g., "dgx-05", "cpu-03")
- `mac` (string, unique) - Primary network interface MAC address for PXE boot
- `category` (string, foreign key) - References Category.name for provisioning profile
- `management_network` (string, foreign key) - References Network.id for PXE boot network
- `power_control` (string, enum: "ipmi") - Power control protocol (always "ipmi" for this module)
- `interfaces` (list of Interface objects) - Network interface configurations
- `bmc_settings` (object) - BMC/IPMI credentials and privilege level
- `roles` (list of strings) - Node role assignments (e.g., ["compute", "gpu"], ["control_plane"])
- `kernel_parameters` (string, optional) - Node-specific kernel boot parameters (overrides category)
- `boot_loader` (string, optional) - Bootloader configuration (overrides category)
- `serial_number` (string, optional) - Hardware serial number for inventory
- `part_number` (string, optional) - Hardware part number for inventory

**Relationships**:
- **1-to-1 with Category** - Each node assigned to exactly one category
- **Many-to-1 with Network** - Multiple nodes share management network
- **1-to-Many with Interface** - Each node has multiple network interfaces
- **1-to-1 with PowerAction** - Each node can have one power action at a time
- **1-to-1 with NodeStatus** - Each node has current state (queried via API)

**Validation Rules**:
- `hostname` must be unique across all BCM devices (enforced by BCM API)
- `mac` must be unique across all devices (enforced by BCM API)
- At least one interface must have `bootable = true` for PXE provisioning
- `category` must reference existing category name (via data source or created resource)

**Terraform Resource**: `bcm_cmdevice_device`

**Example**:
```hcl
resource "bcm_cmdevice_device" "nodes" {
  for_each = var.nodes
  
  hostname           = each.key  # "dgx-05"
  mac                = each.value.mac
  category           = each.value.category
  management_network = local.management_network_id
  power_control      = "ipmi"
  
  bmc_settings = {
    username  = var.bmc_username
    password  = var.bmc_password
    privilege = "ADMINISTRATOR"
  }
  
  interfaces = [
    {
      type     = "bmc"
      name     = "bmc"
      mac      = each.value.bmc_mac
      ip       = each.value.ipmi_ip
      network  = local.oob_network_id
      bootable = false
    },
    {
      type     = "physical"
      name     = "eth0"
      mac      = each.value.mac
      network  = local.management_network_id
      bootable = true  # PXE boot interface
    }
  ]
  
  roles = each.value.roles
}
```

---

### 2. Interface

Represents a network interface on a node (physical Ethernet, bonded, or BMC).

**Attributes**:
- `type` (string, enum: "physical" | "bond" | "bmc") - Interface type
- `name` (string) - Interface name (e.g., "eth0", "bond0", "bmc")
- `mac` (string) - Physical MAC address (required for physical/BMC interfaces)
- `network` (string, foreign key) - References Network.id
- `ip` (string, optional) - Static IP assignment (DHCP if omitted)
- `bootable` (boolean) - Designates interface for PXE boot (only one per device)

**Relationships**:
- **Many-to-1 with Node** - Each interface belongs to exactly one node
- **Many-to-1 with Network** - Multiple interfaces can be on same network

**Validation Rules**:
- Only one interface per device can have `bootable = true`
- `mac` required for `type = "physical"` and `type = "bmc"`
- `bootable` interface SHOULD use `management_network` for consistency

**Terraform Structure**: Nested within `bcm_cmdevice_device.interfaces` list

---

### 3. Category (Provisioning Profile)

Represents a template configuration for node provisioning, defining OS image, installation mode, disk setup, and post-install scripts.

**Attributes**:
- `name` (string, primary key) - Unique category identifier (e.g., "gpu-worker", "control-plane")
- `software_image_proxy` (string, foreign key) - References SoftwareImage.uuid
- `install_mode` (string, enum: "AUTO" | "FULL" | "MINIMAL") - Installation behavior
- `new_node_install_mode` (string, optional) - Override install mode for new nodes
- `bmc_settings` (object) - Default BMC configuration (username, password, privilege)
- `disksetup` (string, XML) - Disk partitioning and filesystem layout configuration
- `initialize_scripts` (list of strings) - Scripts executed before OS installation
- `finalize_scripts` (list of strings) - Scripts executed after OS installation
- `kernel_parameters` (string) - Default kernel boot parameters for all nodes in category
- `boot_loader` (string) - Bootloader configuration (e.g., "grub2")
- `fsmounts` (string, XML) - Filesystem mount configuration
- `modules` (list of strings) - Kernel modules to load
- `roles` (list of strings) - Default roles assigned to nodes in this category
- `gpu_settings` (object, optional) - GPU-specific configuration for DGX nodes
- `services` (list of strings) - System services to enable

**Relationships**:
- **1-to-Many with Node** - One category assigned to many nodes
- **1-to-1 with SoftwareImage** - Each category references exactly one software image

**Validation Rules**:
- `software_image_proxy` must reference existing software image UUID (via data source lookup)
- `install_mode` must be one of: AUTO, FULL, MINIMAL
- `disksetup` must be valid XML conforming to BCM disk setup schema

**Terraform Resource**: `bcm_cmdevice_category` (optional - can use existing categories)

**Example**:
```hcl
resource "bcm_cmdevice_category" "gpu_worker" {
  count = var.create_custom_category ? 1 : 0
  
  name                  = "gpu-worker-custom"
  software_image_proxy  = local.software_image_uuid
  install_mode          = "AUTO"
  
  bmc_settings = {
    username  = var.bmc_username
    password  = var.bmc_password
    privilege = "ADMINISTRATOR"
  }
  
  disksetup = file("${path.module}/templates/gpu-disksetup.xml")
  
  initialize_scripts = [
    "/cm/shared/scripts/pre-install-gpu.sh"
  ]
  
  finalize_scripts = [
    "/cm/shared/scripts/post-install-gpu.sh"
  ]
  
  kernel_parameters = "nvidia-drm.modeset=1 iommu=pt"
  boot_loader       = "grub2"
  
  modules = ["nvidia", "nvidia-uvm", "nvidia-modeset"]
  
  roles = ["compute", "gpu"]
  
  gpu_settings = {
    enable_persistence_mode = true
    compute_mode            = "DEFAULT"
  }
}
```

---

### 4. Software Image

Represents an OS image stored on BCM headnode (pre-existing, managed outside Terraform).

**Attributes**:
- `uuid` (string, primary key) - Immutable unique identifier (used in category foreign keys)
- `name` (string, unique) - Display name (e.g., "ubuntu-22.04-nvidia-535")
- `id` (integer) - BCM internal ID (not used in module)
- `path` (string) - Filesystem path on headnode (e.g., "/cm/images/ubuntu-22.04-nvidia-535")
- `kernel_parameters` (string, optional) - Default kernel parameters baked into image

**Relationships**:
- **1-to-Many with Category** - One software image referenced by many categories

**Validation Rules**:
- Software images MUST pre-exist on BCM headnode before module use
- Module performs data source lookup to validate image existence during plan phase
- `name` must match exactly (case-sensitive)

**Terraform Data Source**: `data.bcm_cmpart_softwareimages`

**Example**:
```hcl
data "bcm_cmpart_softwareimages" "available" {}

locals {
  software_image = [
    for img in data.bcm_cmpart_softwareimages.available.images :
    img if img.name == var.software_image_name
  ][0]
  
  software_image_uuid = local.software_image.uuid
}
```

---

### 5. Network

Represents a network segment configured in BCM (pre-existing, managed outside Terraform).

**Attributes**:
- `id` (string, primary key) - Network identifier (used in device/interface references)
- `uuid` (string) - Alternative unique identifier
- `name` (string, unique) - Display name (e.g., "dgxnet", "oob-mgmt")
- `cidr` (string, optional) - Network CIDR range (e.g., "10.184.162.0/24")

**Relationships**:
- **1-to-Many with Node** - One management network used by many nodes
- **1-to-Many with Interface** - One network contains many interfaces

**Validation Rules**:
- Networks MUST pre-exist in BCM before module use
- Module performs data source lookup to validate network existence during plan phase
- `name` must match exactly (case-sensitive)

**Terraform Data Source**: `data.bcm_cmnet_networks`

**Example**:
```hcl
data "bcm_cmnet_networks" "all" {}

locals {
  management_network = [
    for net in data.bcm_cmnet_networks.all.networks :
    net if net.name == var.management_network_name
  ][0]
  
  management_network_id = local.management_network.id
  
  oob_network = [
    for net in data.bcm_cmnet_networks.all.networks :
    net if net.name == "oob-mgmt"
  ][0]
  
  oob_network_id = local.oob_network.id
}
```

---

### 6. Power Action

Represents an IPMI power control operation (ephemeral, not persisted in state).

**Attributes**:
- `device_id` (string, foreign key) - References Device.id or hostname
- `power_action` (string, enum: "power_on" | "power_off" | "power_cycle" | "power_reset") - Action type
- `wait_for_completion` (boolean) - Block until BMC confirms action executed (default: true)
- `timeout` (integer, seconds) - Maximum wait time for action completion (default: 600)

**Relationships**:
- **Many-to-1 with Node** - Each power action targets exactly one node (but node can have multiple actions over time)

**Validation Rules**:
- `power_action` must be one of: power_on, power_off, power_cycle, power_reset
- `device_id` must reference existing device resource
- Actions are opt-in via `enable_power_action` variable (not auto-triggered)

**Lifecycle**:
- Actions are **ephemeral** - not stored in Terraform state
- Executed during apply when `enable_power_action = true`
- Changing `power_action` value triggers re-execution
- Not re-executed on unchanged applies (idempotency)

**Terraform Resource**: `bcm_cmdevice_power` (Terraform 1.14+ Actions feature)

**Fallback**: `null_resource` + `local-exec` with ipmitool for Terraform <1.14

**Example**:
```hcl
resource "bcm_cmdevice_power" "node_power" {
  for_each = var.enable_power_action ? var.nodes : {}
  
  device_id           = bcm_cmdevice_device.nodes[each.key].id
  power_action        = var.power_action  # "power_on" or "power_cycle"
  wait_for_completion = true
  timeout             = 600  # 10 minutes for PXE boot
  
  depends_on = [bcm_cmdevice_device.nodes]
}
```

---

### 7. Node Status

Represents current provisioning state of a node (queried from BCM API, not stored).

**Attributes**:
- `hostname` (string, primary key) - Node identifier
- `state` (string, enum: "active" | "provisioning" | "failed" | "powered_off" | "unknown") - Current state
- `ip` (string) - Assigned IP address (from management network interface)
- `mac` (string) - Primary MAC address
- `roles` (list of strings) - Assigned roles
- `uuid` (string) - Device UUID in BCM

**Relationships**:
- **1-to-1 with Node** - Each node has exactly one current status

**Validation Rules**:
- Status is read-only (queried via data source, not created by module)
- `state` values determined by BCM provisioning engine:
  - `active` - Provisioning complete, node operational
  - `provisioning` - PXE boot/install in progress
  - `failed` - Provisioning error (timeout, hardware failure)
  - `powered_off` - Node not powered on
  - `unknown` - Node not found in BCM inventory

**Terraform Data Source**: `data.bcm_cmdevice_nodes`

**Example**:
```hcl
data "bcm_cmdevice_nodes" "provisioned" {
  depends_on = [bcm_cmdevice_power.node_power]
}

locals {
  node_status = {
    for hostname, node_config in var.nodes :
    hostname => {
      state   = try([for n in data.bcm_cmdevice_nodes.provisioned.nodes : n.state if n.hostname == hostname][0], "unknown")
      ip      = try([for n in data.bcm_cmdevice_nodes.provisioned.nodes : n.interfaces[0].ip if n.hostname == hostname][0], "")
      success = try([for n in data.bcm_cmdevice_nodes.provisioned.nodes : n.state if n.hostname == hostname][0], "") == "active"
    }
  }
}

output "node_status" {
  value = local.node_status
}
```

---

## Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ Phase 0: Prerequisites (Pre-existing Infrastructure)            │
└─────────────────────────────────────────────────────────────────┘
         │
         │ BCM Headnode has:
         │ - Software images imported
         │ - Networks configured (mgmt + OOB)
         │ - Provisioning role active
         │ - DHCP/TFTP/PXE services running
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 1: Terraform Plan - Data Source Lookups                  │
└─────────────────────────────────────────────────────────────────┘
         │
         ├─► data.bcm_cmpart_softwareimages.available
         │   └─► Filter by var.software_image_name → local.software_image_uuid
         │
         ├─► data.bcm_cmnet_networks.all
         │   └─► Filter by var.management_network_name → local.management_network_id
         │
         └─► data.bcm_cmdevice_categories.available (if using existing)
             └─► Filter by category name → local.category_uuid
         │
         │ Validation: All lookups succeed (images/networks exist)
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 2: Terraform Apply - Resource Creation                    │
└─────────────────────────────────────────────────────────────────┘
         │
         ├─► (Optional) bcm_cmdevice_category.custom
         │   └─► Create custom category with software_image_uuid
         │
         └─► bcm_cmdevice_device.nodes (for_each: var.nodes)
             ├─► Register hostname, MAC, BMC settings
             ├─► Assign category (custom or existing)
             ├─► Configure interfaces (physical + BMC)
             └─► Set management_network, roles
         │
         │ Result: Devices registered in BCM, ready for provisioning
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 3: Power Actions - Trigger Provisioning (Opt-in)         │
└─────────────────────────────────────────────────────────────────┘
         │
         │ Operator sets: enable_power_action=true, power_action=power_on
         │
         └─► bcm_cmdevice_power.node_power (for_each: var.nodes)
             ├─► Send IPMI command to BMC
             ├─► Node powers on → PXE boot
             ├─► Download OS image via TFTP
             ├─► Execute disksetup (partitioning)
             ├─► Install OS from software image
             ├─► Run initialize scripts (pre-install hooks)
             ├─► Run finalize scripts (post-install hooks)
             └─► BCM marks node as "active"
         │
         │ Duration: ~30 minutes per node (sequential) or 30-60 min (parallel)
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 4: Status Query - Verify Provisioning                     │
└─────────────────────────────────────────────────────────────────┘
         │
         └─► data.bcm_cmdevice_nodes.provisioned
             └─► Query each node state, IP, roles
         │
         └─► locals.node_status (aggregated results)
             └─► Output provisioning summary (success/failed/not_found)
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 5: Re-provisioning (Optional) - Update Existing Nodes    │
└─────────────────────────────────────────────────────────────────┘
         │
         │ Operator changes: software_image_name → new image
         │ Operator sets: enable_power_action=true, power_action=power_cycle
         │
         └─► bcm_cmdevice_power.node_power
             ├─► Send IPMI power_cycle command
             ├─► Node reboots → PXE boot with new image
             └─► Re-provision with updated OS/config
         │
         │ Node identity preserved (hostname, MAC, IP remain same)
         │
         ▼
         [Operational Node - Ready for Workloads]
```

---

## State Transitions

### Node Provisioning State Machine

```
┌────────────┐
│ Not Found  │ (Node doesn't exist in BCM)
└─────┬──────┘
      │
      │ bcm_cmdevice_device created
      │
      ▼
┌────────────┐
│ Registered │ (Device record exists, not powered on)
└─────┬──────┘
      │
      │ bcm_cmdevice_power: power_on
      │
      ▼
┌────────────────┐
│ Powered Off    │ (IPMI command dispatched)
└─────┬──────────┘
      │
      │ BMC powers on node, PXE boot starts
      │
      ▼
┌────────────────┐
│ Provisioning   │ (PXE boot, OS install in progress)
└─────┬──────────┘
      │
      ├──────────────────────────────────┐
      │ Success (30 min)                 │ Failure (timeout/error)
      │                                  │
      ▼                                  ▼
┌────────────┐                    ┌────────────┐
│ Active     │                    │ Failed     │
└─────┬──────┘                    └─────┬──────┘
      │                                  │
      │ bcm_cmdevice_power:              │ Investigate logs
      │ power_cycle (re-provision)       │ Fix issue
      │                                  │ Retry power_on
      ▼                                  │
┌────────────────┐                       │
│ Provisioning   │◄──────────────────────┘
└────────────────┘
      │
      │ Re-provision completes
      │
      ▼
┌────────────┐
│ Active     │ (Updated OS image, config applied)
└────────────┘
```

**State Descriptions**:
- **Not Found**: Node doesn't exist in BCM inventory
- **Registered**: Device record created, but node not powered on
- **Powered Off**: Node exists in BCM but hardware is off
- **Provisioning**: PXE boot and OS installation in progress (30 min avg)
- **Active**: Node fully provisioned, OS booted, operational
- **Failed**: Provisioning error (hardware failure, network issue, timeout)

**Operator Actions**:
- `power_on` - Trigger initial provisioning from registered state
- `power_cycle` - Re-provision active node with new image/config
- `power_off` - Graceful shutdown (not used in provisioning workflow)
- `power_reset` - Hard reboot (use for hung provisioning)

---

## Module Variable to Entity Mapping

| Variable | Entity | Attribute | Notes |
|----------|--------|-----------|-------|
| `var.nodes` | Node | All attributes | Map of hostname → node config |
| `var.software_image_name` | SoftwareImage | name | Lookup via data source |
| `var.management_network_name` | Network | name | Lookup via data source |
| `var.category_name` | Category | name | Use existing or create custom |
| `var.install_mode` | Category | install_mode | AUTO/FULL/MINIMAL |
| `var.bmc_username` | Node | bmc_settings.username | Sensitive |
| `var.bmc_password` | Node | bmc_settings.password | Sensitive |
| `var.power_action` | PowerAction | power_action | power_on/power_cycle |
| `var.enable_power_action` | PowerAction | (conditional creation) | Boolean flag |
| `var.provisioning_mode` | PowerAction | depends_on logic | sequential/parallel |

---

## Summary

**Core Entities**: 7 (Node, Interface, Category, SoftwareImage, Network, PowerAction, NodeStatus)

**Relationships**: 
- Node ↔ Category (Many-to-1)
- Node ↔ Network (Many-to-1)
- Node ↔ Interface (1-to-Many)
- Node ↔ PowerAction (1-to-1 ephemeral)
- Category ↔ SoftwareImage (Many-to-1)
- Interface ↔ Network (Many-to-1)

**Key Design Decisions**:
1. **Pre-existing Infrastructure**: SoftwareImages and Networks managed outside module (data sources only)
2. **Optional Category Creation**: Module can create custom categories or reference existing
3. **Ephemeral Power Actions**: Not stored in state, explicitly triggered via variables
4. **Status as Query Result**: Node status queried from API, not created by module
5. **Interface Flexibility**: Support for physical, bond, and BMC interfaces with single bootable designation

**Phase 1 Complete** ✅ → Proceed to contracts generation
