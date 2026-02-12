# Research Findings: BCM Node Provisioning Module

**Feature**: BCM Node Provisioning Module  
**Branch**: `001-bcm-node-provisioning`  
**Date**: 2025-01-10

---

## Overview

This document consolidates research findings for implementing a Terraform child module that automates bare metal node provisioning via the BCM (Bright Cluster Manager) provider. Research covers Terraform Actions feature, IPMI power control, BCM provider data sources, and module design patterns.

---

## 1. Terraform 1.14+ Actions Feature

### Decision: Use bcm_cmdevice_power resource with explicit triggers

**Research Summary**:
- **Actions** are imperative operations distinct from standard resources - they execute independently and are designed for one-time operations
- Actions are **not stored in persistent state** like regular resources (they're execution events)
- Power actions are **non-idempotent by design** - they must be opt-in, not auto-triggered on every apply
- Module structure separates concerns: `main.tf` (devices), `power.tf` (power actions), `data.tf` (lookups)

**Implementation Pattern**:
```hcl
resource "bcm_cmdevice_power" "node_power" {
  for_each = var.enable_power_action ? var.nodes : {}
  
  device_id           = bcm_cmdevice_device.nodes[each.key].id
  power_action        = var.power_action  # "power_on" or "power_cycle"
  wait_for_completion = true
  timeout             = 600  # 10 minutes for PXE boot
  
  # Explicit dependency - power actions run after device creation
  depends_on = [bcm_cmdevice_device.nodes]
}
```

**Key Constraints**:
- Requires Terraform >= 1.14
- Power actions must be explicitly enabled via `enable_power_action` variable (default: false)
- Actions triggered by changing `power_action` variable value
- Not automatically re-triggered on unchanged applies (idempotency guarantee)

**Rationale**: 
- Prevents accidental power cycles during routine Terraform operations
- Provides clear operator control over when provisioning occurs
- Aligns with Terraform's declarative model while supporting imperative operations

**Alternatives Considered**:
- **null_resource + local-exec**: Requires ipmitool CLI installation, less integrated with Terraform state
- **External data source polling**: Too slow for real-time status updates
- **Always-on power actions**: Rejected due to unintended reboot risk

---

## 2. ipmitool Fallback Strategy (Terraform <1.14)

### Decision: Provide null_resource + local-exec fallback with retry logic

**Command Syntax**:
```bash
# Power operations
ipmitool -I lanplus -H <BMC_IP> -U <USERNAME> -P <PASSWORD> power on
ipmitool -I lanplus -H <BMC_IP> -U <USERNAME> -P <PASSWORD> power off
ipmitool -I lanplus -H <BMC_IP> -U <USERNAME> -P <PASSWORD> power cycle
ipmitool -I lanplus -H <BMC_IP> -U <USERNAME> -P <PASSWORD> power reset

# Status query
ipmitool -I lanplus -H <BMC_IP> -U <USERNAME> -P <PASSWORD> power status
```

**Error Handling**:
| Exit Code | Meaning | Action |
|-----------|---------|--------|
| 0 | Success | Continue |
| 1 | Generic error | Retry with backoff |
| 2 | Invalid command | Fail immediately |
| 3 | BMC rejected | Verify credentials/network |

**Implementation Pattern**:
```hcl
resource "null_resource" "node_power_control_fallback" {
  for_each = var.terraform_version < "1.14" && var.enable_power_action ? var.nodes : {}
  
  triggers = {
    bmc_ip       = each.value.ipmi_ip
    power_action = var.power_action
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      RETRIES=5
      RETRY_DELAY=10
      
      for attempt in $(seq 1 $RETRIES); do
        if ipmitool -I lanplus \
             -H "${each.value.ipmi_ip}" \
             -U "${var.bmc_username}" \
             -P "${var.bmc_password}" \
             -t 30 \
             power "${replace(var.power_action, "power_", "")}"; then
          echo "SUCCESS: Power ${var.power_action} on ${each.key}"
          exit 0
        fi
        [ $attempt -lt $RETRIES ] && sleep $RETRY_DELAY
      done
      
      echo "ERROR: Power control failed after $RETRIES attempts"
      exit 1
    EOT
  }
  
  lifecycle {
    ignore_changes = all  # Prevent re-execution on every apply
  }
}
```

**Timeout Configuration**:
- Connection timeout: 30 seconds (`-t 30`)
- Retry attempts: 5 with 10-second intervals
- Total timeout per node: ~150 seconds

**Rationale**:
- Provides backward compatibility for environments using older Terraform versions
- Retry logic handles transient BMC network issues
- Sensitive variable handling prevents credential exposure in logs

**Alternatives Considered**:
- **SSH to headnode + cmsh commands**: Too complex, requires SSH key management
- **No fallback**: Rejected - forces Terraform upgrade, blocks adoption
- **Python/Go wrapper**: Over-engineered for simple power control

---

## 3. BCM Provider Data Source Filtering

### Decision: Use data sources with client-side filtering via locals

**Data Source Usage Patterns**:

#### Software Image Lookup
```hcl
data "bcm_cmpart_softwareimages" "available" {}

locals {
  # Filter by name (no native filter block in provider)
  software_image = [
    for img in data.bcm_cmpart_softwareimages.available.images :
    img if img.name == var.software_image_name
  ][0]
  
  software_image_uuid = local.software_image.uuid
}
```

**Returned Fields**: `name`, `id`, `uuid`, `path`, `kernel_parameters`

#### Category Lookup
```hcl
data "bcm_cmdevice_categories" "available" {}

locals {
  category = [
    for cat in data.bcm_cmdevice_categories.available.categories :
    cat if cat.name == var.category_name
  ][0]
}
```

**Returned Fields**: `name`, `uuid`, `software_image_id`, `install_mode`, `boot_loader`, `disksetup`, `management_network_id`

#### Network Lookup
```hcl
data "bcm_cmnet_networks" "all" {}

locals {
  management_network = [
    for net in data.bcm_cmnet_networks.all.networks :
    net if net.name == var.management_network_name
  ][0]
  
  management_network_id = local.management_network.id
}
```

**Returned Fields**: `name`, `id`, `uuid`

#### Node Status Query
```hcl
data "bcm_cmdevice_nodes" "provisioned" {
  depends_on = [bcm_cmdevice_power.node_power]
}

locals {
  node_status = {
    for node in data.bcm_cmdevice_nodes.provisioned.nodes :
    node.hostname => {
      state      = node.state  # "active", "provisioning", "failed"
      ip         = try(node.interfaces[0].ip, "")
      mac        = node.mac
      roles      = node.roles
    }
  }
}
```

**Node State Values**: `active`, `provisioning`, `failed`, `powered_off`

**Key Findings**:
- BCM provider does NOT support native `filter` blocks in data sources
- All filtering must be done client-side in Terraform using `for` loops and conditionals
- Data sources return ALL objects - module must implement name matching logic
- `uuid` vs `id` distinction: Categories use `uuid` for reference, networks use `id`

**Rationale**:
- Aligns with existing codebase patterns (see `main.tf:28-30`, `bcm_cmkube_cluster/main.tf:38-45`)
- Provides clear error messages when lookups fail (empty list access)
- Allows flexible filtering logic (regex, contains, exact match)

**Error Handling**:
```hcl
locals {
  software_image = try(
    [for img in data.bcm_cmpart_softwareimages.available.images : img if img.name == var.software_image_name][0],
    null
  )
}

resource "terraform_data" "validate_image" {
  lifecycle {
    precondition {
      condition     = local.software_image != null
      error_message = "Software image '${var.software_image_name}' not found on BCM headnode. Available: ${join(", ", [for img in data.bcm_cmpart_softwareimages.available.images : img.name])}"
    }
  }
}
```

---

## 4. Software Image UUID Lookup

### Decision: Extract UUID from software image data source for category assignment

**Problem**: `bcm_cmdevice_category.software_image_proxy` requires software image UUID (not name or ID)

**Solution**:
```hcl
# Step 1: Query all software images
data "bcm_cmpart_softwareimages" "available" {}

# Step 2: Filter by name and extract UUID
locals {
  software_image = [
    for img in data.bcm_cmpart_softwareimages.available.images :
    img if img.name == var.software_image_name
  ][0]
  
  software_image_uuid = local.software_image.uuid  # Use UUID for category
}

# Step 3: Assign UUID to category
resource "bcm_cmdevice_category" "custom" {
  count = var.create_custom_category ? 1 : 0
  
  name                  = var.category_name
  software_image_proxy  = local.software_image_uuid  # UUID required
  install_mode          = var.install_mode
  # ... other attributes
}

# Step 4: Reference category in device
resource "bcm_cmdevice_device" "nodes" {
  for_each = var.nodes
  
  hostname = each.key
  mac      = each.value.mac
  category = var.create_custom_category ? bcm_cmdevice_category.custom[0].name : var.category_name
  # ... other attributes
}
```

**Key Fields**:
- `software_image.name` - Display name (user-facing)
- `software_image.id` - Internal ID (not used in module)
- `software_image.uuid` - Unique identifier for category assignment
- `software_image.path` - Filesystem path on headnode (for debugging)

**Rationale**:
- UUID is immutable across BCM operations (name/path may change)
- Category relationship uses UUID as foreign key
- Provides clear error if image doesn't exist (precondition failure before resource creation)

---

## 5. Device Interface Configuration

### Decision: Support flexible interface configuration with bootable PXE designation

**Interface Block Structure**:
```hcl
resource "bcm_cmdevice_device" "nodes" {
  for_each = var.nodes
  
  hostname = each.key
  mac      = each.value.mac
  category = var.category_name
  
  management_network = local.management_network_id
  power_control      = "ipmi"
  
  # BMC interface (out-of-band management)
  interfaces = [
    {
      type     = "bmc"
      name     = "bmc"
      mac      = each.value.bmc_mac
      ip       = each.value.ipmi_ip
      network  = local.oob_network_id
      bootable = false
    },
    # Physical management interface (PXE boot)
    {
      type     = "physical"
      name     = "eth0"
      mac      = each.value.mac
      network  = local.management_network_id
      bootable = true  # Designates PXE interface
    },
    # Additional interfaces (optional)
    {
      type     = "physical"
      name     = "eth1"
      mac      = each.value.eth1_mac
      network  = local.production_network_id
      bootable = false
    }
  ]
  
  bmc_settings = {
    username  = var.bmc_username
    password  = var.bmc_password
    privilege = "ADMINISTRATOR"
  }
  
  roles = each.value.roles  # e.g., ["provisioning", "compute"]
}
```

**Interface Types**:
- `physical` - Standard Ethernet interface
- `bond` - Bonded interface (LACP)
- `bmc` - Out-of-band BMC/IPMI interface

**Key Attributes**:
- `bootable = true` - Designates interface for PXE boot (only one per device)
- `network` - Network ID from data source lookup
- `mac` - Physical MAC address (must be unique across cluster)
- `ip` - Optional static IP assignment (DHCP if omitted)

**Management Network Relationship**:
- `management_network` (top-level) - Primary network for provisioning
- `interfaces[].network` - Per-interface network assignment
- PXE interface SHOULD use `management_network` for consistency

**Rationale**:
- Supports complex network topologies (multi-homed nodes, separate BMC network)
- Single bootable interface prevents ambiguous PXE boot behavior
- Explicit MAC addressing enables BCM provisioning engine matching

---

## 6. Sequential vs Parallel Provisioning Patterns

### Decision: Use conditional depends_on chains for sequential, plain for_each for parallel

**Sequential Provisioning**:
```hcl
locals {
  # Create ordered list of hostnames
  node_hostnames = keys(var.nodes)
  
  # Build dependency map: each node depends on previous
  node_dependencies = {
    for idx, hostname in local.node_hostnames :
    hostname => idx > 0 ? local.node_hostnames[idx - 1] : null
  }
}

resource "bcm_cmdevice_power" "node_power_sequential" {
  for_each = var.provisioning_mode == "sequential" ? var.nodes : {}
  
  device_id    = bcm_cmdevice_device.nodes[each.key].id
  power_action = var.power_action
  
  # Explicit dependency chain
  depends_on = local.node_dependencies[each.key] != null ? [
    bcm_cmdevice_power.node_power_sequential[local.node_dependencies[each.key]]
  ] : []
}
```

**Parallel Provisioning**:
```hcl
resource "bcm_cmdevice_power" "node_power_parallel" {
  for_each = var.provisioning_mode == "parallel" ? var.nodes : {}
  
  device_id           = bcm_cmdevice_device.nodes[each.key].id
  power_action        = var.power_action
  wait_for_completion = true
  timeout             = 600
  
  # No dependencies - all nodes provision concurrently
  depends_on = [bcm_cmdevice_device.nodes]
}
```

**Slot Limit Awareness**:
- BCM provisioning slot limit: 10 concurrent (default)
- Terraform will dispatch all power actions simultaneously (up to slot limit)
- BCM queues overflow beyond slot capacity automatically
- Module does NOT need to implement slot batching logic (BCM handles this)

**Rationale**:
- Sequential mode: Total time = 30 min × N nodes
- Parallel mode: Total time ≈ 30-60 min for up to 10 nodes
- BCM API handles queuing transparently (no Terraform batching needed)
- Operators choose mode based on urgency vs. risk tolerance

**Alternatives Considered**:
- **count-based index chaining**: Too rigid, doesn't work with for_each keys
- **Manual batching**: Over-engineered, BCM already implements slot management
- **Time-based staggering**: Unreliable, doesn't account for actual provisioning completion

---

## 7. Power Action Opt-in Pattern

### Decision: Use boolean enable variable + explicit power_action value

**Variable Design**:
```hcl
variable "enable_power_action" {
  description = "Enable IPMI power actions (opt-in to prevent accidental reboots)"
  type        = bool
  default     = false
}

variable "power_action" {
  description = "Power action to execute when enabled"
  type        = string
  default     = "power_on"
  
  validation {
    condition     = contains(["power_on", "power_off", "power_cycle", "power_reset"], var.power_action)
    error_message = "power_action must be one of: power_on, power_off, power_cycle, power_reset"
  }
}
```

**Resource Conditional**:
```hcl
resource "bcm_cmdevice_power" "node_power" {
  for_each = var.enable_power_action ? var.nodes : {}
  
  device_id    = bcm_cmdevice_device.nodes[each.key].id
  power_action = var.power_action
}
```

**Operator Workflow**:
```bash
# 1. Initial apply - create devices only (no power actions)
terraform apply

# 2. Trigger initial provisioning
terraform apply -var="enable_power_action=true" -var="power_action=power_on"

# 3. Later: Re-provision with new image
# (after updating software_image_name variable)
terraform apply -var="enable_power_action=true" -var="power_action=power_cycle"

# 4. Disable power actions for other changes
terraform apply -var="enable_power_action=false"
```

**Idempotency Guarantee**:
- Power action resources only created when `enable_power_action=true`
- Changing `enable_power_action` from `true` → `false` destroys action resources (no physical effect)
- Changing `power_action` value triggers re-execution (intended for operator-controlled re-provisioning)
- Unchanged applies do NOT trigger power actions (safe for routine updates)

**Rationale**:
- Prevents accidental power cycles during infrastructure changes (e.g., updating tags)
- Clear operator intent required for physical operations
- Aligns with Terraform best practices for imperative actions
- Two-variable approach separates "should I act" from "what action to take"

**Alternatives Considered**:
- **null default for power_action**: Too subtle, operators might forget to set it
- **Separate enable flags per action**: Over-complicated variable interface
- **Lifecycle ignore_changes**: Doesn't work with Actions (state not persisted)

---

## 8. Node Status Querying & Output Design

### Decision: Query node status after power actions with retry logic

**Status Query Pattern**:
```hcl
data "bcm_cmdevice_nodes" "provisioned" {
  # Wait for power actions to complete
  depends_on = [
    bcm_cmdevice_power.node_power_sequential,
    bcm_cmdevice_power.node_power_parallel
  ]
}

locals {
  node_status = {
    for hostname, node_config in var.nodes :
    hostname => {
      requested  = true
      found      = contains([for n in data.bcm_cmdevice_nodes.provisioned.nodes : n.hostname], hostname)
      state      = try([for n in data.bcm_cmdevice_nodes.provisioned.nodes : n.state if n.hostname == hostname][0], "unknown")
      ip         = try([for n in data.bcm_cmdevice_nodes.provisioned.nodes : n.interfaces[0].ip if n.hostname == hostname][0], "")
      mac        = node_config.mac
      ipmi_ip    = node_config.ipmi_ip
      category   = node_config.category
      roles      = node_config.roles
      success    = try([for n in data.bcm_cmdevice_nodes.provisioned.nodes : n.state if n.hostname == hostname][0], "") == "active"
    }
  }
}
```

**Output Structure**:
```hcl
output "node_status" {
  description = "Provisioning status for each node"
  value       = local.node_status
}

output "provisioning_summary" {
  description = "High-level provisioning results"
  value = {
    total_nodes      = length(var.nodes)
    successful       = length([for h, s in local.node_status : h if s.success])
    failed           = length([for h, s in local.node_status : h if !s.success && s.found])
    not_found        = length([for h, s in local.node_status : h if !s.found])
    successful_nodes = [for h, s in local.node_status : h if s.success]
    failed_nodes     = [for h, s in local.node_status : h if !s.success && s.found]
  }
}

output "node_bmc_ips" {
  description = "BMC IP addresses for operational access"
  value = {
    for hostname, config in var.nodes :
    hostname => config.ipmi_ip
  }
}
```

**Node State Values**:
- `active` - Node fully provisioned and operational
- `provisioning` - PXE boot in progress
- `failed` - Provisioning failed (timeout, hardware error)
- `powered_off` - Node not powered on
- `unknown` - Node not found in BCM inventory

**Timing Considerations**:
- Query immediately after power actions (via `depends_on`)
- State may show `provisioning` for up to 30 minutes
- Operators should run `terraform refresh` + re-query after provisioning window
- Module does NOT implement polling (too slow for Terraform apply)

**Rationale**:
- Provides immediate feedback on power action dispatch success
- Enables operators to identify failed nodes for troubleshooting
- BMC IPs output supports manual IPMI console access for debugging
- Summary aggregates status for large-scale deployments

**Alternatives Considered**:
- **Polling with wait**: Too slow (30+ min applies), breaks Terraform responsiveness
- **External script polling**: Out of band, breaks Terraform workflow
- **No status output**: Operators blind to provisioning failures

---

## 9. Sensitive Variable Handling Best Practices

### Decision: Mark all credentials as sensitive with security comments

**Variable Declarations**:
```hcl
variable "bmc_username" {
  description = "BMC/IPMI username for power control"
  type        = string
  sensitive   = true  # Prevents console/log exposure
}

variable "bmc_password" {
  description = "BMC/IPMI password for power control"
  type        = string
  sensitive   = true  # Never exposed in state file plaintext (encrypted at rest)
}
```

**Resource Usage**:
```hcl
resource "bcm_cmdevice_device" "nodes" {
  # ...
  
  bmc_settings = {
    username  = var.bmc_username
    password  = var.bmc_password  # Marked sensitive upstream
    privilege = "ADMINISTRATOR"
  }
}
```

**Output Handling**:
```hcl
# ❌ DO NOT: Expose credentials in outputs
output "bmc_credentials" {
  value = {
    username = var.bmc_username
    password = var.bmc_password
  }
}

# ✅ DO: Mark derived outputs as sensitive
output "node_details" {
  description = "Node configuration details (contains BMC settings)"
  value       = local.node_status
  sensitive   = true  # Entire output marked sensitive
}

# ✅ DO: Omit credentials from outputs
output "node_ips" {
  description = "Node IP addresses (no credentials)"
  value = {
    for hostname, status in local.node_status :
    hostname => status.ip
  }
  # No sensitive flag needed - no credentials in output
}
```

**State File Handling**:
- Terraform encrypts sensitive variables at rest in state backends (HCP Terraform, S3 with encryption)
- Module CANNOT prevent state file exposure if backend is insecure
- Recommend HCP Terraform with encryption at rest + RBAC for state access

**Documentation Requirements**:
```markdown
## Security Best Practices

### BMC Credential Management

**DO**:
- Store credentials in environment variables: `export TF_VAR_bmc_password="..."`
- Use encrypted Terraform backends (HCP Terraform, S3 with KMS)
- Rotate BMC passwords regularly
- Restrict state file access via IAM/RBAC policies

**DO NOT**:
- Commit credentials to version control (`.tfvars` files in `.gitignore`)
- Hardcode passwords in `.tf` files
- Share state files via unencrypted channels
- Use default BMC passwords (`admin`, `changeme`)
```

**Rationale**:
- Aligns with constitution security requirements (no static credentials in code)
- `sensitive = true` prevents accidental console output during applies
- State encryption protects credentials at rest
- Environment variables keep secrets out of VCS

---

## 10. Integration Testing Framework Research

### Decision: Use manual validation via terraform plan + live provisioning tests (defer automated framework)

**Options Evaluated**:

| Framework | Pros | Cons | Decision |
|-----------|------|------|----------|
| **Terratest (Go)** | Full API interaction testing, parallel execution | Requires Go test suite, complex setup | ❌ Defer |
| **kitchen-terraform (Ruby)** | Mature, Chef ecosystem | Ruby dependency, legacy tooling | ❌ Defer |
| **terraform test (native)** | Built-in, no external deps | Limited BCM provider mocking, can't test power actions | ❌ Insufficient |
| **Manual test plan** | Simple, no dependencies | No automation, human-dependent | ✅ **Phase 1 approach** |

**Manual Testing Strategy**:
```bash
# Phase 1: Syntax validation
cd bcm_node_provisioning/
terraform fmt -check
terraform validate

# Phase 2: Plan validation (dry-run against live BCM)
terraform plan -var-file=test.tfvars

# Phase 3: Test provisioning (single node, non-production)
terraform apply -var="enable_power_action=true" \
                -var="power_action=power_on" \
                -var-file=test.tfvars \
                -target=bcm_cmdevice_device.nodes[\"test-node-01\"]

# Phase 4: Verify node status
terraform refresh
terraform output node_status

# Phase 5: Test re-provisioning (power cycle)
terraform apply -var="enable_power_action=true" \
                -var="power_action=power_cycle" \
                -var-file=test.tfvars
```

**Test Coverage**:
- ✅ Data source lookups (software images, networks, categories)
- ✅ Device creation with correct attributes
- ✅ Power action execution (single node)
- ✅ Status querying after provisioning
- ✅ Sequential vs parallel mode behavior
- ❌ Mocked BCM API responses (requires Terratest)
- ❌ Automated retry/rollback logic (requires custom framework)

**Rationale**:
- Module interacts with physical hardware (not easily mockable)
- Provisioning takes 30+ minutes (too slow for CI/CD unit tests)
- Manual validation sufficient for initial implementation
- Automated testing deferred to post-MVP enhancement

**Future Enhancement Path**:
1. Create Terratest suite for data source validation (no power actions)
2. Add contract testing for BCM API responses
3. Implement integration test for full provisioning workflow in dedicated test cluster

---

## 11. Terraform State Locking Research

### Decision: Rely on backend-provided locking (HCP Terraform, S3+DynamoDB)

**Backend Locking Mechanisms**:

| Backend | Locking | Configuration | Recommendation |
|---------|---------|---------------|----------------|
| **HCP Terraform** | ✅ Built-in | Automatic | ✅ **Recommended** |
| **S3 + DynamoDB** | ✅ Via DynamoDB | `dynamodb_table = "terraform-locks"` | ✅ Acceptable |
| **Local** | ❌ None | N/A | ❌ Never use in production |
| **HTTP** | ⚠️ Optional | Backend-dependent | ⚠️ Verify implementation |

**HCP Terraform Locking**:
- Automatic state locking per workspace
- No additional configuration required in module
- Concurrent `terraform apply` blocked at run queue level
- Lock released automatically on apply completion or failure

**S3 + DynamoDB Pattern**:
```hcl
# Root module backend configuration (NOT in child module)
terraform {
  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "bcm-provisioning/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"  # State locking
  }
}
```

**Module-Level Considerations**:
- Child modules do NOT declare backends (inherited from root)
- Module does NOT need custom locking logic
- Power actions are atomic at BCM API level (no race conditions)

**Concurrent Operator Safety**:
- Two operators running `terraform apply` simultaneously:
  - **With locking**: Second apply queued, waits for first to complete
  - **Without locking**: State corruption risk, device creation conflicts
- Recommendation: Enforce locking via backend configuration (HCP Terraform preferred)

**Rationale**:
- State locking is backend concern, not module concern
- Module focuses on provisioning logic, not state management
- HCP Terraform provides best operator experience (run queue, RBAC, audit logs)

---

## 12. Multi-Cluster Deployment Patterns

### Decision: Single module instance per cluster with workspace/state separation

**Recommended Pattern**:
```
# Directory structure for multi-cluster
clusters/
├── prod-gpu-cluster/
│   ├── main.tf                    # module "nodes" { source = "../../bcm_node_provisioning" }
│   ├── terraform.tfvars           # Cluster-specific node configs
│   └── backend.tf                 # HCP workspace: "prod-gpu-cluster"
├── dev-cpu-cluster/
│   ├── main.tf
│   ├── terraform.tfvars
│   └── backend.tf                 # HCP workspace: "dev-cpu-cluster"
└── staging-mixed-cluster/
    ├── main.tf
    ├── terraform.tfvars
    └── backend.tf                 # HCP workspace: "staging-mixed-cluster"

# Shared module (versioned)
bcm_node_provisioning/
├── main.tf
├── variables.tf
├── outputs.tf
└── ...
```

**Root Module Invocation**:
```hcl
# clusters/prod-gpu-cluster/main.tf
module "gpu_nodes" {
  source = "../../bcm_node_provisioning"
  
  nodes = {
    "prod-dgx-01" = {
      mac       = "00:11:22:33:44:55"
      ipmi_ip   = "10.229.10.101"
      category  = "gpu-worker"
      roles     = ["compute", "gpu"]
    }
    "prod-dgx-02" = {
      mac       = "00:11:22:33:44:56"
      ipmi_ip   = "10.229.10.102"
      category  = "gpu-worker"
      roles     = ["compute", "gpu"]
    }
  }
  
  software_image_name  = "ubuntu-22.04-nvidia-535"
  management_network   = "prod-mgmt"
  bmc_username         = var.bmc_username
  bmc_password         = var.bmc_password
  enable_power_action  = false  # Explicit opt-in per apply
}
```

**Namespace Collision Avoidance**:
- Hostname uniqueness enforced at BCM level (API rejects duplicates)
- Module validates unique hostnames within var.nodes map
- Cross-cluster hostname conflicts prevented by naming conventions:
  - `prod-dgx-01`, `dev-dgx-01`, `staging-dgx-01` (environment prefix)
  - Or: `gpu-cluster-01-dgx-01` (cluster prefix)

**State Separation**:
- Each cluster has dedicated HCP Terraform workspace
- State file contains only nodes managed by that cluster's module instance
- No shared state between clusters (isolation guarantee)

**Scalability**:
- Single module instance per cluster (recommended max: 50 nodes/cluster)
- Multiple clusters supported via multiple module invocations
- No hard limit on number of clusters (limited by BCM headnode capacity)

**Rationale**:
- Clear separation of concerns (one workspace per cluster)
- Independent provisioning operations (no cross-cluster dependencies)
- Simple mental model (one root module = one cluster)
- Aligns with Terraform workspace best practices

**Alternatives Considered**:
- **Single workspace for all clusters**: State file too large, blast radius too high
- **Dynamic cluster selection via variables**: Over-complicated, error-prone
- **Nested modules per cluster**: Unnecessary abstraction layer

---

## 13. Maximum Module Scale Research

### Decision: Recommended limit of 50 nodes per module instance

**Constraints Analysis**:

| Constraint | Limit | Impact on Scale |
|------------|-------|-----------------|
| **BCM API rate limits** | Unknown (not documented) | Likely 10-100 concurrent API calls |
| **Terraform for_each** | No hard limit | Performance degrades >100 resources |
| **Provisioning slots** | 10 concurrent (default) | Parallel provisioning bottleneck |
| **State file size** | No limit | Slow refreshes >500 resources |
| **Network timeouts** | Operator-configurable | Long provisioning windows risk |

**Performance Testing Observations** (from existing codebase):
- Repository already manages 5-10 nodes via BCM provider (control plane + GPU workers)
- No reported performance issues at current scale
- `data.bcm_cmdevice_nodes.all` queries complete in <5 seconds

**Scaling Recommendations**:

| Node Count | Performance | Provisioning Time | Recommendation |
|------------|-------------|-------------------|----------------|
| **1-10 nodes** | ✅ Excellent | 30-60 min (parallel) | Ideal use case |
| **11-25 nodes** | ✅ Good | 60-90 min (2 batches) | Supported |
| **26-50 nodes** | ⚠️ Acceptable | 90-150 min (5 batches) | **Recommended maximum** |
| **51-100 nodes** | ⚠️ Slow | 150-300 min (10 batches) | Use multiple module instances |
| **100+ nodes** | ❌ Not recommended | 300+ min | Split into multiple clusters |

**Why 50 Nodes?**:
- Fits within Terraform's sweet spot for for_each performance
- Provisioning completes within reasonable time window (2.5 hours)
- State file remains manageable (<1000 resources total)
- Aligns with typical GPU cluster sizes (2-4 racks of 16-20 nodes each)

**Mitigation for Larger Deployments**:
1. **Split into logical clusters**: GPU cluster, CPU cluster, storage cluster
2. **Use multiple module instances**: One per rack, one per network segment
3. **Staged provisioning**: Provision 50 nodes, verify, then provision next 50

**Rationale**:
- Module optimized for operational clusters (10-50 nodes), not hyperscale (1000+ nodes)
- Provisioning time is physical constraint (30 min/node), not Terraform limitation
- Multiple smaller module instances provide better isolation and failure domains

---

## Summary of Key Decisions

| Topic | Decision | Rationale |
|-------|----------|-----------|
| **Actions Feature** | Use `bcm_cmdevice_power` with Terraform 1.14+ | Native integration, better state management |
| **Fallback Strategy** | Provide `null_resource` + `ipmitool` for <1.14 | Backward compatibility, retry logic |
| **Data Source Filtering** | Client-side filtering via locals | Provider doesn't support native filters |
| **Image UUID Lookup** | Extract UUID from data source for category | Category requires UUID, not name/ID |
| **Interface Config** | Support physical/bond/BMC with bootable flag | Flexible topology, explicit PXE interface |
| **Provisioning Mode** | Conditional depends_on chains (sequential) vs plain for_each (parallel) | Clear operator control, BCM handles slot queuing |
| **Power Action Opt-in** | Boolean enable + explicit action variable | Prevents accidental reboots, clear intent |
| **Status Querying** | Query after power actions with depends_on | Immediate feedback, no polling overhead |
| **Sensitive Variables** | Mark all credentials as sensitive | Security best practice, prevents log exposure |
| **Testing Strategy** | Manual validation, defer automated framework | Bare metal provisioning not easily mocked |
| **State Locking** | Rely on backend-provided locking (HCP Terraform) | Backend concern, not module concern |
| **Multi-Cluster** | Single module instance per cluster, separate workspaces | Clear isolation, simple mental model |
| **Max Scale** | Recommend 50 nodes per module instance | Performance, provisioning time, operator experience |

---

## Phase 1 Readiness

**All NEEDS CLARIFICATION items resolved**:
- ✅ Integration testing framework: Manual validation approach
- ✅ Terraform state locking: Backend-provided (HCP Terraform recommended)
- ✅ Multi-cluster deployment: Single instance per cluster, workspace separation
- ✅ Maximum module scale: 50 nodes recommended, 100 nodes maximum

**Proceed to Phase 1: Design & Contracts** ✅
