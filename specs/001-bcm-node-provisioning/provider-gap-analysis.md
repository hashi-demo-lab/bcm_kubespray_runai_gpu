# BCM Provider Gap Analysis — Reprovisioning Use Cases

**Date:** 2026-02-23
**Source:** https://github.com/hashi-demo-lab/terraform-provider-bcm (main branch, SHA: f803c2d)
**Deployed:** v0.1.6 (local binary on bcm-head-01)
**Changelog:** v0.1.0 (Unreleased) — no released versions yet

---

## Executive Summary

The deployed provider (v0.1.6 local build) and the GitHub source (main branch) are the **same codebase** — there are no unreleased reprovisioning features. The provider has **no built-in support** for:

- Software image assignment on devices
- Reprovisioning triggers (provision_on_apply)
- Node state polling (WaitForNodeReady)
- Install mode selection (AUTO/FULL/NOSYNC)

These are all required for proper reprovisioning. This document itemizes every gap and the provider changes needed to close them.

### Architecture Rules

1. **Software image is the primary use case.** Setting/changing the software image on nodes 
   is the most common operation. Category changes are rare.
2. **Reprovisioning triggers ONLY on software image change.** The provider reads the current 
   image from BCM (`cmdevice.getDevice`), compares to the desired value — if same, no reboot, 
   no changes. `provision_on_apply` is a conditional gate, not an unconditional reboot flag.
3. **Terraform MUST NOT issue power commands** for reprovisioning. No `cmdevice.powerCycle`, 
   no `cmdevice.powerReset`. Power operations are the responsibility of the BCM head node.
4. **No workarounds.** If the provider lacks a feature, document it as a gap — do not create 
   cmsh `local-exec`, `terraform_data`, or shell script workarounds.
5. **Terraform's role:** Set device properties (`software_image`, `provision_on_apply = true`, 
   `next_install_mode`) and let BCM handle the reprovision lifecycle.
6. **BCM head node's role:** Receive the device update, trigger reboot via internal IPMI, 
   manage PXE boot, image sync, and node state transitions.

### Target Terraform Code (After Provider Changes)

The nodes are already imported into Terraform state with hostname, mac, interfaces, 
etc. defined in `main.tf`. For reprovisioning, **4 fields** are needed beyond the existing 
resource definition — `category` (existing but may change) plus 3 new fields:

```hcl
resource "bcm_cmdevice_device" "nodes" {
  for_each = var.nodes

  # --- EXISTING (already in main.tf, unchanged for reprovisioning) ---
  hostname           = each.key                        # Required — for clarity
  mac                = each.value.mac

  # --- NEW (added for reprovisioning) ---
  category           = local.category_uuid_map[each.value.category]  # May change (rare)
  software_image     = each.value.software_image       # Gap 1 — per-node image, primary trigger
  provision_on_apply = true                            # Gap 2 — tells BCM to trigger reboot ONLY if image changed
  next_install_mode  = var.install_mode                # Gap 3 — defaults to AUTO
}
```

**Node targeting:** Each node has its own `software_image` in `var.nodes`. To reprovision 
specific nodes, change only their image in tfvars. The provider compares each node's desired 
image to its current image in BCM — same image = no-op, no reboot. Only nodes with a 
different image get reprovisioned.

```hcl
# Example tfvars — only dgx-05 gets reprovisioned
nodes = {
  cpu-03 = { software_image = "ubuntu2204-4"       ... }  # Same as current → no-op
  cpu-05 = { software_image = "ubuntu2204-4"       ... }  # Same as current → no-op
  dgx-05 = { software_image = "ubuntu2204-4-cuda"  ... }  # Different → reprovision
}
```

---

## Current Provider Capabilities (from GitHub source)

### `bcm_cmdevice_device` Resource — What EXISTS

| Field | Type | Notes |
|-------|------|-------|
| `hostname` | Required | RFC 1123 validated |
| `mac` | Required | Forces replacement |
| `category` | Required | UUID reference (validated) |
| `management_network` | Optional+Computed | UUID reference |
| `partition` | Optional+Computed | UUID, resolved from category |
| `power_control` | Optional | "none", "ipmi", "ipdu", "redfish" |
| `notes` | Optional | Free text |
| `kernel_parameters` | Optional | Boot parameters |
| `boot_loader` | Optional+Computed | SYSLINUX, GRUB |
| `boot_loader_protocol` | Optional+Computed | HTTP, TFTP |
| `force` | Optional | Override BCM validation |
| `default_gateway` | Optional | IPv4 |
| `serial_number` | Optional+Computed | Hardware |
| `part_number` | Optional+Computed | Hardware |
| `roles` | Optional+Computed | Set of role names |
| `interfaces` | Block (list) | Full multi-interface support |
| `kubelet_role` | Block (list) | K8s cluster membership |
| `etcd_host_role` | Block (list) | etcd cluster membership |

### `interfaces` Block — What EXISTS

| Field | Type | Notes |
|-------|------|-------|
| `name` | Required | e.g., "eth0", "BOOTIF", "ipmi" |
| `type` | Required | "physical", "bond", "bmc" |
| `network` | Optional | UUID reference |
| `mac` | Optional | MAC address |
| `ip` | Optional | Static IPv4 |
| `ipv6_ip` | Optional | Static IPv6 |
| `dhcp` | Optional | Default: **true** ⚠️ |
| `bootable` | Optional | Default: false |
| `start_if` | Optional | ALWAYS, NEVER, HOTPLUG |
| `members` | Optional | Bond member names |
| `bond_mode` | Optional | 802.3ad, active-backup, etc. |

### `bcm_cmdevice_power` Action — What EXISTS

| Field | Type | Notes |
|-------|------|-------|
| `device_id` | Required | UUID or hostname |
| `power_action` | Required | power_on, power_off, reboot, power_cycle |
| `wait_for_completion` | Optional | **NOT IMPLEMENTED** (TODO in code) |
| `timeout` | Optional | Go duration format |

**Key limitation:** `wait_for_completion` has a TODO comment — it sends the power command but does NOT poll for state changes.

### Data Sources — What EXISTS

| Data Source | Notes |
|-------------|-------|
| `bcm_cmdevice_nodes` | Lists nodes with hostname, id, mac, status, category |
| `bcm_cmdevice_categories` | Lists categories |
| `bcm_cmdevice_roles` | Lists roles |
| `bcm_cmnet_networks` | Lists networks |
| `bcm_cmpart_softwareimages` | Lists software images (name, uuid) |
| `bcm_cmpart_partitions` | Lists partitions |

### CRUD Operations — What EXISTS

| Operation | Method | Notes |
|-----------|--------|-------|
| Create | `cmdevice.addDevice` | Full device creation with interfaces, roles |
| Read | `cmdevice.getDevice` | Returns complete device state |
| Update | `cmdevice.updateDevice` | Updates device, preserves interface UUIDs |
| Delete | `cmdevice.removeDevice` | Simple deletion, no decommission |
| Import | `ImportState` | Passthrough by UUID |

---

## What's MISSING for Reprovisioning

> **Primary use case:** Setting/changing the software image on nodes. Category changes are 
> rare. Reprovisioning is triggered ONLY when the software image changes — the provider must 
> read the current software image from BCM (`cmdevice.getDevice`), compare it to the desired 
> value, and only trigger a reprovision if they differ. Same image = no reboot, no changes.

### Gap 1: No `software_image` Field on Device Resource

**Impact:** CRITICAL — Cannot assign a software image to a node via Terraform

**This is the primary reprovisioning field.** The BCM API supports setting `softwareImage` 
on a device (the image that will be deployed when the node is reprovisioned). The provider 
does not expose this field.

**Current behavior:** The category's default partition/image is used. There is no way to 
override the image per-device.

**Required provider change:**

```go
// Add to CMDeviceDeviceResourceModel struct
SoftwareImage types.String `tfsdk:"software_image"` // Optional, image name or UUID

// Add to Schema
"software_image": schema.StringAttribute{
    Optional:            true,
    MarkdownDescription: "Software image name to deploy on this device. Overrides the category default. " +
        "This is the primary reprovisioning trigger — when this value changes (compared to " +
        "the current image on the node via cmdevice.getDevice), and provision_on_apply is true, " +
        "BCM will reprovision the node. If the value matches the current image, nothing happens.",
},
```

**Read behavior:** On Read/Refresh, the provider MUST query `cmdevice.getDevice` and read 
the current `softwareImage` value from BCM. This is the source of truth for determining 
whether a change occurred — NOT the Terraform state alone.

**API mapping:** `softwareImage` field in the `cmdevice.updateDevice` JSON-RPC payload.

**BCM cmsh equivalent:** `device; use <hostname>; set softwareimage <name>; commit`

---

### Gap 2: No Reprovisioning Trigger via BCM Head Node

**Impact:** CRITICAL — Cannot trigger reprovisioning from Terraform

**Architecture rule:** Terraform MUST NOT issue power commands directly (no `cmdevice.powerCycle`, 
no `cmdevice.powerReset`). Power operations are the responsibility of the BCM head node. 
Terraform's role is to update device properties (software image, install mode) and then signal 
BCM to reprovision — BCM decides how to handle the power cycle internally.

**Trigger logic:** `provision_on_apply` is NOT an unconditional reboot flag. It is a 
**conditional gate** — reprovisioning ONLY occurs when ALL of these are true:

1. `provision_on_apply = true` on the device resource
2. `software_image` value differs from the current image on the node (queried via `cmdevice.getDevice`)

If the software image is the same → **nothing happens**. No reboot, no reprovision, no state change.
If `provision_on_apply = false` → the new image is written to BCM's database but the node is NOT rebooted.

**Required provider change:**

```go
// Add to CMDeviceDeviceResourceModel struct
ProvisionOnApply types.Bool `tfsdk:"provision_on_apply"` // Optional, default: false

// Add to Schema
"provision_on_apply": schema.BoolAttribute{
    Optional:            true,
    MarkdownDescription: "When true and software_image changes (compared to the current image " +
        "on the node), signals BCM head node to reprovision the node and waits for it to reach " +
        "UP state. If software_image has not changed, this flag has no effect. Default: false.",
},
```

**Behavior in Update function:**
1. Read current device from BCM via `cmdevice.getDevice`
2. Compare current `softwareImage` to the plan's `software_image` value
3. If **same** → no reprovision, update other fields only (if any changed)
4. If **different** AND `provision_on_apply = true`:
   a. Write new `software_image` to BCM via `cmdevice.updateDevice`
   b. Signal BCM head node to reprovision (e.g. `cmdevice.imageUpdate` or equivalent BCM API 
      that triggers reprovisioning — NOT a direct power command)
   c. Poll `cmdevice.getDevice` every 15s until status = "UP"
   d. Verify the node's reported `softwareImage` matches the expected image
5. If **different** AND `provision_on_apply = false`:
   a. Write new `software_image` to BCM via `cmdevice.updateDevice`
   b. No reboot — image takes effect on next natural restart
6. If timeout exceeded, write state anyway with warning

**Important:** The exact BCM API method for triggering a head-node-managed reprovision needs 
to be identified. Candidates: `cmdevice.imageUpdate`, `cmdevice.provision`, or a flag on 
`cmdevice.updateDevice` that tells BCM to reprovision after the update. The provider must 
NOT use `cmdevice.powerCycle` or `cmdevice.powerReset` directly.

**Category changes do NOT trigger reprovisioning.** Category changes are metadata-only updates 
in BCM's database. They do not cause a reboot. If a category change requires reprovisioning 
(e.g., new disk layout), the operator must also change the software image or manually reboot.

---

### Gap 3: No `next_install_mode` Field

**Impact:** MEDIUM — Cannot control installation strategy

BCM supports three install modes that determine how aggressively the node is reprovisioned:

| Mode | Behavior |
|------|----------|
| `AUTO` | Check partitions, incremental rsync if healthy (fast) |
| `FULL` | Repartition + full image sync (slow, required for category changes) |
| `NOSYNC` | Skip rsync, preserve local disk |

**Required provider change:**

```go
// Add to CMDeviceDeviceResourceModel struct
NextInstallMode types.String `tfsdk:"next_install_mode"` // Optional

// Add to Schema
"next_install_mode": schema.StringAttribute{
    Optional:            true,
    MarkdownDescription: "Installation mode for next provisioning cycle. " +
        "AUTO (incremental rsync), FULL (repartition + full sync), NOSYNC (skip rsync). " +
        "This is a one-shot setting that resets to category default after one boot.",
    Validators: []validator.String{
        stringvalidator.OneOf("AUTO", "FULL", "NOSYNC"),
    },
},
```

**API mapping:** `nextInstallMode` field in the device entity. One-shot — BCM resets it after boot.

**BCM cmsh equivalent:** `device; use <hostname>; set installmode FULL; commit`

---

### Gap 4: `wait_for_completion` Not Implemented in Power Action

**Impact:** HIGH — Power action fires and forgets

**Architecture note:** Terraform should NOT issue direct power commands for reprovisioning.
The `bcm_cmdevice_power` action exists for emergency/operational use only (e.g., hard power 
off a stuck node). For reprovisioning, use `provision_on_apply` (Gap 2) which signals the 
BCM head node to manage the reprovision lifecycle.

The `bcm_cmdevice_power` action has `wait_for_completion` in its schema but the implementation is a TODO:

```go
// From action_cmdevice_power.go line ~220
if waitForCompletion {
    resp.SendProgress(action.InvokeProgressEvent{
        Message: "Power command sent. Waiting for state change is not yet implemented.",
    })
    // TODO: Implement wait_for_completion polling logic in Phase 4 (User Story 3)
}
```

**Required provider change:**
- Implement polling loop: call `cmdevice.getDevice` every 15s
- Check `status` field progression: DOWN → BOOTING → INSTALLING → UP
- Respect `timeout` parameter (default 5m, range 10s-30m)
- Abort on ERROR or INSTALL_FAILED states
- Return final status in progress events
- **This action should NOT be used for reprovisioning** — it's for operational power control only

---

### Gap 5: No Node Status/State Computed Fields

**Impact:** MEDIUM — Cannot read back provisioning state after operations

The device resource model has no `status` or `provisioning_state` computed fields. The BCM API returns these on `getDevice`, but they're not mapped to the Terraform state.

**Required provider change:**

```go
// Add to CMDeviceDeviceResourceModel struct
Status            types.String `tfsdk:"status"`             // Computed: UP, DOWN, BOOTING, etc.
ProvisioningState types.String `tfsdk:"provisioning_state"` // Computed: detailed provisioning phase

// Add to Schema
"status": schema.StringAttribute{
    Computed:            true,
    MarkdownDescription: "Current device status (UP, DOWN, BOOTING, INSTALLING, etc.)",
},
"provisioning_state": schema.StringAttribute{
    Computed:            true,
    MarkdownDescription: "Detailed provisioning state",
},
```

**API mapping:** `status` and `provisioningState` from `cmdevice.getDevice` response.

---

### Gap 6: DHCP Defaults to `true` on Interfaces

**Impact:** HIGH — This is the root cause of the original incident

From `resource_cmdevice_device_interfaces.go`:

```go
// Configuration flags with defaults
if !iface.DHCP.IsNull() && !iface.DHCP.IsUnknown() {
    entity["dhcp"] = iface.DHCP.ValueBool()
} else {
    entity["dhcp"] = true // Default ← DANGEROUS
}
```

When an interface is created without explicitly setting `dhcp = false`, BCM receives `dhcp: true` and overwrites any existing static IP configuration.

**Required provider change:**

Option A (safer default): Change default to `false` for management interfaces
```go
entity["dhcp"] = false // Safe default — require explicit opt-in for DHCP
```

Option B (schema-level): Add a validator that requires `dhcp` to be explicitly set when `ip` is provided
```go
// Cross-field validation in interfaces block
// If ip is set, dhcp must be explicitly false
```

Option C (document only): Keep `true` default but add prominent warnings in docs

**Recommendation:** Option A — default `dhcp` to `false`. Static IPs are the norm for bare metal management interfaces. DHCP should require explicit opt-in.

---

### Gap 7: No `softwareImage` Data Source (Single Image Lookup)

**Impact:** LOW — `bcm_cmpart_softwareimages` exists but only does list/filter

Currently, there's only `bcm_cmpart_softwareimages` (plural) which returns a filtered list. A singular `bcm_cmpart_softwareimage` data source for exact name lookup would be cleaner:

```hcl
data "bcm_cmpart_softwareimage" "target" {
  name = "ubuntu2204-4"  # Exact match
}

resource "bcm_cmdevice_device" "node" {
  software_image = data.bcm_cmpart_softwareimage.target.name
  # ...
}
```

**This is nice-to-have.** The existing plural data source works, just requires extracting `[0]` from the result list.

---

### Gap 8: Update Sends Full Entity — No Partial Updates

**Impact:** CRITICAL — Changing one field overwrites all others

The provider's Update function builds a **complete device entity** (hostname, mac, category, 
interfaces, roles, partition) and sends it as a single `cmdevice.updateDevice` call. BCM 
replaces the entire device with what was sent. This means:

- Changing `software_image` also re-sends interfaces → risk of overwriting ipmi0
- Changing `category` also re-sends roles → risk of removing BCM-managed roles
- Any field missing from the entity gets reset to BCM defaults

This is why `lifecycle { ignore_changes = all }` exists — it prevents ANY updates.

**Required provider change:**

Option A — Surgical update (only send changed fields):
```go
entity := map[string]interface{}{"uuid": state.UUID.ValueString()}
if plan.SoftwareImage.ValueString() != state.SoftwareImage.ValueString() {
    entity["softwareImage"] = plan.SoftwareImage.ValueString()
}
if plan.Category.ValueString() != state.Category.ValueString() {
    entity["category"] = plan.Category.ValueString()
}
// Never include interfaces, roles, hostname, mac unless explicitly changed
```

Option B — Read-modify-write (read current from BCM, overlay changes, send back):
```go
currentDevice := client.CallJSONRPC("cmdevice", "getDevice", uuid)
currentDevice["softwareImage"] = plan.SoftwareImage.ValueString()
client.CallJSONRPC("cmdevice", "updateDevice", currentDevice)
```

**Recommendation:** Option B is safer — it preserves all BCM-managed fields by reading 
the current state first, then only overlaying the fields the user explicitly changed.

---

## Summary: Provider Changes Required

| # | Gap | Severity | Change Type | Estimated Effort |
|---|-----|----------|-------------|-----------------|
| 1 | `software_image` field on device | CRITICAL | New schema field + Create/Update/Read logic | Medium |
| 2 | `provision_on_apply` trigger | CRITICAL | New field + signal BCM head node to reprovision + polling (NO direct power commands) | High |
| 3 | `next_install_mode` field | MEDIUM | New schema field + API mapping | Low |
| 4 | `wait_for_completion` polling | HIGH | Implement TODO in power action | Medium |
| 5 | `status`/`provisioning_state` computed | MEDIUM | New computed fields + Read mapping | Low |
| 6 | DHCP default `true` → `false` | HIGH | Default change + migration/docs | Low |
| 7 | Singular softwareimage data source | LOW | New data source | Low |
| 8 | Update sends full entity (no partial updates) | CRITICAL | Read-modify-write or surgical update in Update() | Medium |

### Dependency Order

```
Gap 6 (DHCP default)     ← No dependencies, fix first
Gap 5 (status fields)    ← No dependencies
Gap 8 (partial updates)  ← No dependencies, fix early — blocks safe use of Gaps 1+3
Gap 1 (software_image)   ← Prerequisite for Gap 2, requires Gap 8
Gap 3 (install_mode)     ← Prerequisite for Gap 2, requires Gap 8
Gap 2 (provision_on_apply) ← Depends on Gap 1, 3, 5
Gap 4 (wait_for_completion) ← Depends on Gap 5
Gap 7 (data source)      ← Independent, nice-to-have
```

---

## Available Resources Not Yet Used

The provider already has resources for managing image and category lifecycles natively in
Terraform. These are available but not currently used in `bcm_node_provisioning`:

| Resource | Purpose | Reprovisioning Role |
|----------|---------|-------------------|
| `bcm_cmpart_softwareimage` | Create, clone, update, delete OS images | Manages the **image library** — build golden images, clone for patching, set kernel params. Does NOT assign images to devices. |
| `bcm_cmdevice_category` | Create, update, delete device categories | Manages **category definitions** — disk layout, boot config, roles. Does NOT assign categories to devices (that's on `bcm_cmdevice_device`). |

**Important distinction:** These resources manage the image/category **objects themselves**,
not the image-to-device or category-to-device **assignment**. The assignment happens on
`bcm_cmdevice_device` — which is where Gap 1 (`software_image` field) is missing.

Example of what's possible today vs what's missing:

```hcl
# ✅ AVAILABLE: Create/clone a software image
resource "bcm_cmpart_softwareimage" "cuda_12" {
  name           = "ubuntu2204-cuda-12.2"
  original_image = data.bcm_cmpart_softwareimages.base.images[0].uuid  # clone from
  notes          = "CUDA 12.2 image for GPU nodes"
}

# ✅ AVAILABLE: Create a category
resource "bcm_cmdevice_category" "gpu_worker" {
  name = "gpu-a100"
  # ... disk layout, boot config, etc.
}

# ❌ MISSING (Gap 1): Assign image to device
resource "bcm_cmdevice_device" "node" {
  hostname       = "dgx-05"
  category       = bcm_cmdevice_category.gpu_worker.uuid
  software_image = bcm_cmpart_softwareimage.cuda_12.name  # ← DOES NOT EXIST in schema
}
```

---

## Current Workarounds in `bcm_node_provisioning` Module

> **Rule #9:** No workarounds. These exist only because the provider lacks features. They 
> must NOT be extended or replicated. They will be removed once the corresponding provider 
> gaps are resolved.

These cmsh workarounds exist because the provider lacks the features above:

| Workaround | File | cmsh Command | Eliminated By |
|-----------|------|--------------|---------------|
| Category update | `power.tf:11-21` | `cmsh -c 'device; use X; set category Y; commit'` | Gap 8 (partial updates) + removing `ignore_changes = all` |
| Power action | `power.tf:40-53` | `cmsh -c 'device; power -n X reset'` | Gap 2 (`provision_on_apply` — BCM triggers reboot, not Terraform) |
| `lifecycle { ignore_changes = all }` | `main.tf:78-80` | N/A | Gap 8 (partial updates — safe to update individual fields) |

**All three workarounds become unnecessary once Gaps 1, 2, and 8 are resolved.**

---

## BCM API Methods Available (from `bcm_client.go`)

The BCM client already supports these JSON-RPC methods that the provider can leverage:

| Method | Purpose | Used by Provider? |
|--------|---------|------------------|
| `cmdevice.addDevice` | Create node | ✅ Yes |
| `cmdevice.updateDevice` | Update node (category, image, interfaces) | ✅ Yes |
| `cmdevice.getDevice` | Read node state | ✅ Yes |
| `cmdevice.removeDevice` | Delete node | ✅ Yes |
| `cmdevice.powerOn` | Power on | ✅ Yes (via action) — operational only, NOT for reprovisioning |
| `cmdevice.powerOff` | Power off | ✅ Yes (via action) — operational only, NOT for reprovisioning |
| `cmdevice.reboot` | Reboot | ✅ Yes (via action) — operational only, NOT for reprovisioning |
| `cmdevice.powerCycle` | Hard power cycle | ✅ Yes (via action) — operational only, NOT for reprovisioning |
| `cmdevice.getDevices` | List all nodes | ✅ Yes (data source) |
| `CMPart.getSoftwareImage` | Get image details | ✅ Yes (partition resolver) |

**No new API methods are needed.** All required BCM API capabilities exist — the provider just needs to expose them through the Terraform schema and implement the orchestration logic.

**Reprovisioning trigger:** When `provision_on_apply = true` and `software_image` changes, 
the provider should signal BCM to reprovision via `cmdevice.updateDevice` (with appropriate 
flags or a dedicated reprovision API). BCM's head node handles the power cycle internally — 
Terraform never issues direct power commands for reprovisioning.
