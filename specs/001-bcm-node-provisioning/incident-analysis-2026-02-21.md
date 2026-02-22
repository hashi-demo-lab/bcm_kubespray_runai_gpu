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

## Remediation Plan

### Step 1: Clean up state
```bash
terraform state rm 'terraform_data.power_action[0]'
# Also remove category_update state entries to prevent cmsh re-fire
terraform state rm 'terraform_data.category_update["cpu-03"]'
terraform state rm 'terraform_data.category_update["cpu-05"]'
terraform state rm 'terraform_data.category_update["cpu-06"]'
```

### Step 2: Code changes

| File | Change |
|------|--------|
| `main.tf` | Remove ipmi0 dynamic interface block. Keep `power_control = "ipmi0"` attribute. |
| `power.tf` | Remove `timestamp()` from `triggers_replace`. Keep power action resource. |
| `variables.tf` | Make `management_ip` required (not optional). Remove `oob_network_name`, `bmc_username`, `bmc_password`, `ipmi_ip` from schema. |
| `locals.tf` | Remove `oob_network_matches`, `oob_network_id`. |
| `outputs.tf` | Remove `node_bmc_ips` output. |
| `sandbox.auto.tfvars` | Add `management_ip` to each node. Remove `ipmi_ip`, `bmc_*`, `oob_network_name`. |

### Step 3: Validate
```bash
terraform validate
terraform plan  # Expect: no changes (lifecycle ignore_changes = all)
```

### Step 4: Verify connectivity
```bash
ping -c1 10.184.162.102  # cpu-03
ping -c1 10.184.162.104  # cpu-05
ping -c1 10.184.162.121  # cpu-06
```

---

## Key Takeaways

1. **Static IPs are non-negotiable** — BCM's own default is static. DHCP on the management interface is a design error.
2. **Terraform should not manage OOB interfaces** — ipmi0 is BCM-internal infrastructure.
3. **Never use `timestamp()` in triggers** — it turns any gated resource into a time bomb that fires on every apply.
4. **Power actions need static IPs as a prerequisite** — the reprovisioning flow depends on step 4 (CMDaemon reconnect via static IP).
5. **All BCM API calls go through the head node** — Terraform never talks to individual nodes directly.
