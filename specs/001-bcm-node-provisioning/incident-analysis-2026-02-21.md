# BCM Node Provisioning — Incident Analysis & Remediation Discussion

**Date:** 2026-02-21
**Context:** Post-incident analysis after power_cycle via IPMI left 3 control plane nodes in unconfigured state

---

## Timeline

### Incident (2026-02-17)

A `terraform apply` executed `cmsh -c 'device; power -n cpu-03,cpu-05,cpu-06 reset'` which power-cycled all 3 control plane nodes via IPMI. After reboot, the nodes came up with misconfigured network interfaces (DHCP instead of static IPs), leaving them unreachable at their expected management IPs.

**State at time of incident:**
```
terraform_data.power_action[0]:
  triggers_replace = {
    action    = "power_cycle"
    nodes     = "cpu-03,cpu-05,cpu-06"
    timestamp = "2026-02-17T06:56:06Z"
  }
```

**Nodes were manually restored** to operational state prior to this analysis.

### Analysis (2026-02-21)

#### Current Terraform plan shows:

```
terraform_data.power_action[0] will be destroyed
  (because index [0] is out of range for count)

Changes to Outputs:
  ~ device_details: category UUIDs changed (cosmetic — lifecycle ignore_changes = all)
  ~ power_action_enabled = true -> false
```

#### State inspection confirmed:

- All 3 device resources exist: `bcm_cmdevice_device.nodes["cpu-03|05|06"]`
- BOOTIF interfaces have `dhcp = true` — Terraform overwrote BCM's pre-existing static IPs with DHCP
- ipmi0 interfaces present with correct IPMI IPs on ipminet
- `power_action_enabled` still shows `true` in outputs (stale)
- `provisioning_summary`: 3 failed, 0 success
- All 3 nodes now reachable at expected IPs (manually fixed): 10.184.162.102, .104, .121

---

## Root Cause Analysis

### Four compounding failures:

1. **`management_ip` was optional and omitted from tfvars** — The nodes had pre-existing static IP assignments in BCM. When Terraform created the device resources via `cmdevice.addDevice`, it sent the BOOTIF interface with `ip = null` (because `management_ip` was omitted). BCM interpreted this as "use DHCP", **overwriting the existing static assignments**.

2. **ipmi0 (BMC) interface managed by Terraform** — The OOB BMC interface on ipminet (10.229.10.0/24) was created in the device resource via a dynamic block. BCM already manages these interfaces natively. Terraform adding them introduced unnecessary coupling.

3. **`timestamp()` in power action triggers** — The `triggers_replace` block included `timestamp = timestamp()`, which guarantees re-execution on EVERY apply when `enable_power_action = true`. This made the power action a time bomb.

4. **Hard IPMI reset after static IPs were overwritten** — The power_cycle triggered PXE reboot. With DHCP instead of the original static IPs on BOOTIF, step 4 of the reprovisioning flow (CMDaemon reconnect) failed.

---

## Research Findings (BCM Documentation)

### Management interface determination

**BOOTIF on dgxnet (10.184.162.0/24) is THE management interface.** Evidence:

1. `provisioninginterface` defaults to BOOTIF (bcm-node-provisioning-reference.md §3.9) — BCM uses this for all node management: PXE boot, provisioning, status polling, CMDaemon communication.

2. Default node interface values (bcm10-configuring-cluster.md):
   - Network device name: BOOTIF
   - Network: internalnet (our equivalent: dgxnet)
   - IP address: Auto-assigned static (10.141.0.1+)

3. `management_allowed` is a property on the **network**, not the interface. dgxnet is our management-allowed network.

4. BOOTIF is a BCM abstraction — auto-translates to the actual physical NIC name (eth0, ens3, etc.) at boot time based on which interface PXE-booted.

### Management path

```
BCM Head Node → dgxnet → BOOTIF (on each node) → node's static IP on dgxnet
```

### ipmi0 role

The BMC/ipmi0 interface is a **separate out-of-band channel used ONLY for power control** (on/off/reset). It is NOT the management interface. BCM manages nodes through BOOTIF on dgxnet.

### Reprovisioning flow (confirmed correct)

```
Step 1: Terraform → Head Node API → cmdevice.powerreset → BCM sends IPMI cmd via ipmi0
Step 2: Node PXE boots over BOOTIF on dgxnet → picks up image from head node
Step 3: Node-installer provisions new image over BOOTIF on dgxnet (rsync)
Step 4: Node comes up with STATIC IP on BOOTIF/dgxnet → CMDaemon reconnects → status = UP
```

Step 4 is what failed — the original static IPs had been overwritten with DHCP, so CMDaemon couldn't reconnect reliably.

### API call routing

**All API calls go to the head node only.** The Terraform provider never talks directly to individual nodes. For 3 nodes, it's 3 separate JSON-RPC calls to the same head node (`https://<head_node>:8081`), each passing a different hostname. The head node orchestrates IPMI commands internally.

---

## Decision Record

### Interface policy

| Interface | Network | CIDR | Purpose | Terraform Manages? |
|-----------|---------|------|---------|-------------------|
| **BOOTIF** | dgxnet | 10.184.162.0/24 | Management, PXE, SSH, K8s | **YES — static IP required** |
| ipmi0 | ipminet | 10.229.10.0/24 | Power control trigger only | **NO — BCM-internal** |

### Static IP assignments

| Node | Management IP (BOOTIF/dgxnet) | IPMI IP (ipmi0/ipminet) |
|------|-------------------------------|------------------------|
| cpu-03 | 10.184.162.102 | 10.229.10.5 |
| cpu-05 | 10.184.162.104 | 10.229.10.14 |
| cpu-06 | 10.184.162.121 | 10.229.10.13 |

### Power action policy

- `power_control = "ipmi0"` kept as device attribute (BCM needs this for power management)
- ipmi0 interface block removed from Terraform (BCM manages it natively)
- Power actions retained but made safe: `timestamp()` removed, static IPs required
- Power actions gated behind `enable_power_action` (default: false)

---

## Remediation — Implemented Changes (2026-02-23)

### Summary

Four commits on branch `001-bcm-node-provisioning` address the root cause and add operational safety:

### 1. Prevent DHCP override on BOOTIF interface (`1e7de6c`)

| File | Change | Why |
|------|--------|-----|
| `main.tf` | Added `dhcp = false` and `bootable = true` to BOOTIF interface block | Explicitly prevents BCM from falling back to DHCP regardless of other parameters |
| `variables.tf` | Changed `management_ip` from `optional(string)` to `string` (required) | Root cause fix — Terraform will refuse to plan if any node is missing a static IP |
| `variables.tf` | Added IPv4 format validation for `management_ip` | Catches invalid IPs before they reach the BCM API |
| `variables.tf` | Fixed corrupted description (heredoc content accidentally inserted) | Restored correct variable documentation |
| `power.tf` | Removed `timestamp = timestamp()` from `triggers_replace` | Eliminates the time bomb — power actions only fire when action or node list changes |
| `incident-analysis.md` | Updated root cause to reflect "Terraform overwrote static IPs" | Corrected narrative: nodes HAD static IPs, Terraform replaced them with DHCP |

### 2. Auto-import existing BCM nodes (`a748cc9`)

| File | Change | Why |
|------|--------|-----|
| `main.tf` | Added `data.bcm_cmdevice_nodes.existing` data source | Queries BCM for all existing nodes at plan time |
| `main.tf` | Added `import` block with `for_each` | Automatically imports existing BCM nodes into Terraform state by UUID, preventing `addDevice` from overwriting existing configs |

**How it works:**
```
Plan phase:
  1. data.bcm_cmdevice_nodes.existing → queries BCM API for all nodes
  2. local.existing_node_ids → maps hostname → UUID
  3. import block → for each node in var.nodes that exists in BCM
     but NOT in Terraform state, import it by UUID
  4. lifecycle { ignore_changes = all } → no modifications to imported device
```

This eliminates the scenario where Terraform sends `addDevice` with `ip = null` and overwrites an existing static IP assignment with DHCP.

**State refresh behavior:**
- Every `terraform plan` calls the provider's `Read()` function → queries BCM → updates state with current values
- `ignore_changes = all` only prevents Terraform from *pushing changes back* to BCM
- State always reflects BCM reality — outputs show current values
- If BCM changes a value externally (e.g., category in BCM UI), state updates on next plan

### 3. Selective node targeting (`3642b77`)

| File | Change | Why |
|------|--------|-----|
| `variables.tf` | Added `target_nodes` variable (list of hostnames, default `[]`) | Allows targeting specific nodes for actions without removing others from tfvars |
| `variables.tf` | Added validation: all `target_nodes` must exist in `var.nodes` | Prevents typos from silently targeting no nodes |
| `locals.tf` | Added `local.targeted_nodes` computed from `target_nodes` | Filters `var.nodes` to selected subset; empty list = all nodes |
| `power.tf` | Changed `category_update` to iterate `local.targeted_nodes` | Category updates only apply to targeted nodes |

**Operational model:**
```
var.nodes         = { cpu-03, cpu-05, cpu-06 }   ← all nodes always defined
var.target_nodes  = ["cpu-03"]                    ← only cpu-03 gets actions

Result:
  Device resources:  imported for ALL 3 nodes (auto-import from BCM)
  Category updates:  only cpu-03
  Power actions:     only cpu-03 (when enable_power_action = true)
  State refresh:     ALL 3 nodes refreshed from BCM on every plan
```

### 4. Remove IPMI/OOB from reprovisioning module (`2bbefb1`)

| File | Change | Why |
|------|--------|-----|
| `main.tf` | Removed ipmi0 dynamic interface block | BMC interfaces are managed by BCM natively; imported as-is via auto-import |
| `variables.tf` | Removed `ipmi_ip` from node schema | Not needed — BCM already has BMC config; import reads it |
| `variables.tf` | Removed `oob_network_name` variable | No longer referenced after ipmi0 block removal |
| `locals.tf` | Removed `oob_network_matches` and `oob_network_id` locals | No longer referenced |
| `outputs.tf` | Removed `node_bmc_ips` output | IPMI IPs are BCM-internal; not relevant to reprovisioning |

**Design decision:** This module is scoped to **reprovisioning existing nodes** — not creating new ones. All nodes are assumed to already exist in BCM. A separate node creation module will be built in a future phase for initial device provisioning, including BMC interface registration.

### State cleanup

The stale `terraform_data.power_action[0]` and orphaned cpu-05/cpu-06 resources were removed from state via direct state file replacement (local backend lock bug prevented `terraform state rm`):

```bash
terraform state pull > state.json
cat state.json | jq 'del(.resources[] | select(...))' > state_clean.json
cat state_clean.json | jq '.serial += 1' > terraform.tfstate
```

### sandbox.auto.tfvars (final configuration)

```hcl
bcm_endpoint             = "https://localhost:8081"
bcm_username             = "ibm"
bcm_password             = "<redacted>"
bcm_insecure_skip_verify = true
bcm_timeout              = 30

nodes = {
  "cpu-03" = {
    mac           = "B8:59:9F:E4:22:12"
    category      = "default"
    management_ip = "10.184.162.102"
    roles         = []
  }
  "cpu-05" = {
    mac           = "B8:CE:F6:D9:47:BC"
    category      = "default"
    management_ip = "10.184.162.104"
    roles         = []
  }
  "cpu-06" = {
    mac           = "98:03:9B:17:E7:C6"
    category      = "default"
    management_ip = "10.184.162.121"
    roles         = []
  }
}

target_nodes            = ["cpu-03"]
management_network_name = "dgxnet"
software_image_name     = "ubuntu2204-4"
enable_power_action     = false
```

### Validation steps

```bash
git pull origin 001-bcm-node-provisioning
# Update sandbox.auto.tfvars (remove ipmi_ip, oob_network_name; add target_nodes)
terraform plan -lock=false
# Expected: import 3 nodes, category_update for cpu-03 only, 0 device changes
terraform apply -lock=false
```

---

## Key Takeaways

1. **Static IPs are non-negotiable** — BCM's own default is static. DHCP on the management interface is a design error.
2. **Auto-import prevents state drift** — existing BCM nodes are adopted, never recreated.
3. **Never use `timestamp()` in triggers** — it turns any gated resource into a time bomb that fires on every apply.
4. **Target nodes for actions, not for existence** — all nodes stay defined; `target_nodes` controls which ones receive operations.
5. **Power actions need static IPs as a prerequisite** — the reprovisioning flow depends on step 4 (CMDaemon reconnect via static IP).
6. **All BCM API calls go through the head node** — Terraform never talks to individual nodes directly.
