# Implementation Plan: BCM Node Provisioning Module

**Branch**: `001-bcm-node-provisioning` | **Date**: 2025-01-10 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-bcm-node-provisioning/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Create a reusable Terraform child module (`bcm_node_provisioning/`) that automates bare metal node provisioning and re-provisioning via BCM API using IPMI/PXE boot. The module orchestrates device registration, category assignment, software image lookup, and power actions to provision DGX GPU workers and CPU control plane nodes from powered-off state to fully operational cluster members. Technical approach leverages BCM provider resources (bcm_cmdevice_device, bcm_cmdevice_category) with data source lookups for existing infrastructure, and uses Terraform 1.14+ Actions feature (bcm_cmdevice_power) for IPMI power control with sequential/parallel provisioning modes.

## Technical Context

**Language/Version**: HCL (Terraform) >= 1.14 (required for Actions feature)  
**Primary Dependencies**: 
  - BCM Provider: `hashi-demo-lab/bcm ~> 0.1` (pre-configured in root providers.tf)
  - BCM 10 headnode with API access, DHCP, TFTP, PXE, DNS, CA services
  - ipmitool (fallback for Terraform <1.14)

**Storage**: 
  - Terraform state managed remotely (HCP Terraform or equivalent backend)
  - No local state management
  - No persistent data storage beyond Terraform state

**Testing**: 
  - `terraform fmt` for formatting validation
  - `terraform validate` for syntax validation
  - `terraform plan` for dry-run validation against live BCM API
  - Manual validation via test provisioning in non-production environment
  - NEEDS CLARIFICATION: Integration test framework for provisioning workflows

**Target Platform**: 
  - BCM 10 bare metal provisioning infrastructure
  - DGX GPU workers (dgx-05: 10.184.162.109, dgx-06: 10.184.162.110)
  - CPU control plane nodes (cpu-03, cpu-05, cpu-06)
  - Production network: 10.184.162.0/24
  - OOB/IPMI network: 10.229.10.0/24

**Project Type**: Terraform child module (reusable infrastructure component)

**Performance Goals**: 
  - Single node provisioning: <30 minutes (PXE boot to operational)
  - Sequential provisioning: ~30 min per node
  - Parallel provisioning: all nodes complete within 60 min (up to 10 concurrent via slot limit)
  - Data source lookups: <5 seconds per query
  - IPMI power action execution: <10 seconds for command dispatch

**Constraints**: 
  - BCM provisioning slot limit: 10 concurrent (configurable in /etc/cmd.conf)
  - Terraform version requirement: >= 1.14 for Actions feature (older versions need fallback)
  - Network isolation: IPMI traffic confined to OOB network (10.229.10.0/24)
  - Credential security: BMC passwords must not appear in state/logs (sensitive variables)
  - Idempotency: Power actions must be opt-in, not auto-triggered on every apply
  - NEEDS CLARIFICATION: Terraform state locking mechanism for concurrent operator usage
  - NEEDS CLARIFICATION: Maximum supported nodes per module instance

**Scale/Scope**: 
  - Initial deployment: 5 nodes (2 GPU workers + 3 control plane)
  - Production scale: 10-50 nodes per cluster
  - Module structure: 7 files (main.tf, variables.tf, outputs.tf, data.tf, power.tf, locals.tf, versions.tf, README.md)
  - Estimated module LOC: 300-500 lines
  - Variables: ~15-20 input variables
  - Outputs: ~5-10 status outputs
  - NEEDS CLARIFICATION: Multi-cluster deployment pattern (single module instance per cluster?)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Applicable Principles

**✅ Module-First Architecture**: This feature creates a reusable child module for consumption, aligning with module-first approach. The module encapsulates BCM provider resource patterns for node provisioning.

**✅ Specification-Driven Development**: Feature has comprehensive specification (spec.md) with explicit requirements (FR-001 to FR-052), user stories with acceptance criteria, success criteria, and edge cases. No "vibe-coding" - all design decisions traceable to spec.

**✅ Security-First Automation**:
- BMC credentials handled via sensitive variables (FR-031, FR-032)
- No static credentials in code (FR-033)
- IPMI network isolation documented (FR-034)
- Credentials never committed to version control

**✅ File Organization**: Module follows standard Terraform structure:
- `main.tf` - Core resources (device, category)
- `data.tf` - Data sources (images, networks, categories, nodes)
- `power.tf` - Power actions (IPMI operations)
- `variables.tf` - Input declarations with validation
- `outputs.tf` - Status outputs
- `locals.tf` - Computed values
- `versions.tf` - Provider constraints
- `README.md` - Documentation with prerequisites

**✅ Naming Conventions**: Will follow HashiCorp naming standards for resources, variables (snake_case), and module structure.

**✅ Variable Management**: All variables will include descriptions, type constraints, and validation blocks per constitution.

**✅ Security Best Practices**: 
- Sensitive variable marking for credentials
- No hardcoded secrets
- Security rationale comments included
- Pre-commit hooks for validation (repository level)

**✅ Documentation Requirements**: README.md will include purpose, prerequisites (10 documented prerequisites from FR-041 to FR-050), deployment instructions, troubleshooting guide, and example usage.

**✅ Version Control**: Module will be in dedicated directory with proper Git workflow (feature branch, PR to dev).

**✅ State Management**: Remote state assumed (HCP Terraform or equivalent) - no local backend. Backend configuration at root level, not in module.

**✅ Dependency Management**: Provider version constrained to `hashi-demo-lab/bcm ~> 0.1` in versions.tf.

### Constitutional Alignment Status: **PASS ✅**

No violations detected. This is a module creation project (not module consumption), so Module-First Architecture principle applies in reverse - we are creating a module FOR consumption by application teams. All security, documentation, and code quality principles are satisfied by the specification requirements.

### Gates

**Gate 1 - Security Review**: ✅ PASS
- BMC credentials managed securely via sensitive variables
- No static secrets in code
- Network isolation documented

**Gate 2 - Documentation Completeness**: ✅ PASS
- Comprehensive spec with 52 functional requirements
- Prerequisites documented (FR-041 to FR-050)
- README.md mandatory in module structure

**Gate 3 - Specification Quality**: ✅ PASS
- 4 user stories with independent testing
- Edge cases documented (10 scenarios)
- Success criteria measurable (SC-001 to SC-010)

**Proceed to Phase 0: Research** ✅

## Project Structure

### Documentation (this feature)

```text
specs/001-bcm-node-provisioning/
├── spec.md              # Feature specification (existing)
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output - Research findings
├── data-model.md        # Phase 1 output - Entity relationships
├── quickstart.md        # Phase 1 output - Quick start guide
└── contracts/           # Phase 1 output - API/interface contracts
    ├── device-schema.json       # Device resource schema
    ├── category-schema.json     # Category resource schema
    ├── power-action-schema.json # Power action schema
    └── module-interface.md      # Module input/output interface
```

### Source Code (repository root)

```text
bcm_node_provisioning/              # New Terraform child module
├── main.tf                         # Device and category resources
│   ├── bcm_cmdevice_device         # Node device registration
│   └── bcm_cmdevice_category       # Category management (optional)
├── data.tf                         # Data source lookups
│   ├── bcm_cmpart_softwareimages   # Software image lookup by name
│   ├── bcm_cmdevice_categories     # Category lookup
│   ├── bcm_cmnet_networks          # Network lookup by name
│   └── bcm_cmdevice_nodes          # Node status query
├── power.tf                        # IPMI power management
│   ├── bcm_cmdevice_power          # Terraform 1.14+ Actions
│   └── null_resource + local-exec  # Fallback for older TF versions
├── variables.tf                    # Input variable declarations
│   ├── nodes (map of node configs)
│   ├── software_image_name
│   ├── management_network
│   ├── power_action (power_on/power_cycle)
│   ├── provisioning_mode (sequential/parallel)
│   ├── bmc_username (sensitive)
│   ├── bmc_password (sensitive)
│   └── [validation blocks]
├── outputs.tf                      # Status outputs
│   ├── node_status
│   ├── node_ips
│   ├── node_bmc_ips
│   └── provisioning_results
├── locals.tf                       # Computed values
│   ├── software_image_id
│   ├── network_id
│   └── node_count
├── versions.tf                     # Provider constraints
│   ├── terraform >= 1.14
│   └── bcm ~> 0.1
└── README.md                       # Module documentation
    ├── Prerequisites checklist (10 items)
    ├── Usage examples (new + re-provision)
    ├── Variables documentation
    ├── Outputs documentation
    └── Troubleshooting guide

# Existing root module files (unchanged)
providers.tf                        # BCM provider config (already exists)
main.tf                             # Root module using child module
variables.tf                        # Root-level variables
outputs.tf                          # Root-level outputs
terraform.tf                        # Backend configuration
```

**Structure Decision**: 

This is a **Terraform child module** creation project, which doesn't fit the typical "single/web/mobile" project categories. The module will be created as a standalone directory (`bcm_node_provisioning/`) at the repository root, following Terraform module best practices:

1. **Self-contained module**: All module files in dedicated directory for reusability
2. **Clear separation**: Module files separate from root module (repository root already has main.tf, providers.tf, etc.)
3. **Standard Terraform structure**: Follows HashiCorp module layout conventions
4. **No tests/ directory initially**: Testing done via `terraform plan` against live BCM (integration testing framework is marked NEEDS CLARIFICATION in Technical Context)

The root module will consume this child module via:
```hcl
module "node_provisioning" {
  source = "./bcm_node_provisioning"
  
  nodes               = var.nodes
  software_image_name = var.software_image_name
  # ... other variables
}
```

## Complexity Tracking

> **No violations detected - section intentionally minimal**

This feature aligns with constitution principles:
- Creates a reusable module (Module-First Architecture producer)
- No direct resource sprawl (resources encapsulated in module)
- Standard Terraform patterns (no unnecessary abstraction layers)
- Security controls implemented via specification requirements

---

## Phase 0: Research & Outline

### Research Tasks

Based on Technical Context "NEEDS CLARIFICATION" items and BCM provider-specific requirements:

1. **Terraform 1.14+ Actions Feature**: Research `bcm_cmdevice_power` resource implementation, action execution behavior, idempotency guarantees, and state management for ephemeral actions.

2. **ipmitool Fallback Strategy**: Research null_resource + local-exec pattern for IPMI power control when Terraform <1.14, command syntax for ipmitool (power on/off/cycle/reboot), error handling, and timeout configuration.

3. **BCM Provider Data Source Filtering**: Research filtering capabilities for `data.bcm_cmpart_softwareimages`, `data.bcm_cmdevice_categories`, `data.bcm_cmnet_networks` to handle scenarios where multiple results exist for same name.

4. **Software Image UUID Lookup**: Research how `bcm_cmdevice_category.software_image_proxy` expects UUID vs ID vs name, and how to extract correct identifier from `data.bcm_cmpart_softwareimages` for category assignment.

5. **Device Interface Configuration**: Research `bcm_cmdevice_device.interfaces` block structure for physical/bond/BMC interfaces, bootable flag placement, and relationship between interfaces and management_network.

6. **Sequential vs Parallel Provisioning**: Research Terraform dependency management patterns using `depends_on` chains for sequential, `for_each` without dependencies for parallel, and how to implement slot limit awareness.

7. **Power Action Opt-in Pattern**: Research variable design patterns to make power actions explicit (not auto-triggered), including null defaults, conditional resource creation, and lifecycle ignore_changes for device resources.

8. **Node Status Querying**: Research `data.bcm_cmdevice_nodes` response structure, state field values (provisioning/active/failed), timing considerations for querying (during vs after provisioning), and how to map status to outputs.

9. **Sensitive Variable Handling**: Research Terraform sensitive variable best practices for passwords in state file, marking outputs as sensitive, and preventing console/log exposure.

10. **Integration Testing Framework**: Research options for automated testing of Terraform modules that interact with live APIs (Terratest, kitchen-terraform, terraform test), tradeoffs for bare metal provisioning scenarios.

11. **Terraform State Locking**: Research state locking mechanisms for HCP Terraform vs S3/DynamoDB backends, concurrent operator safety, and module-level locking considerations.

12. **Multi-cluster Deployment Patterns**: Research whether single module instance can manage multiple clusters, best practices for workspace/state separation, and namespace collision avoidance for device hostnames.

13. **Maximum Module Scale**: Research BCM API rate limits, Terraform resource count limits, performance implications of managing 50+ node devices in single module instance.

### Research Dispatch

✅ **Research Complete** - See `research.md` for consolidated findings:

1. ✅ Terraform 1.14+ Actions feature researched
2. ✅ ipmitool fallback strategy defined
3. ✅ BCM provider data source patterns documented
4. ✅ Software image UUID lookup pattern defined
5. ✅ Device interface configuration structure documented
6. ✅ Sequential vs parallel provisioning patterns defined
7. ✅ Power action opt-in pattern designed
8. ✅ Node status querying approach determined
9. ✅ Sensitive variable handling best practices documented
10. ✅ Integration testing strategy defined (manual validation)
11. ✅ Terraform state locking approach clarified (backend-provided)
12. ✅ Multi-cluster deployment patterns defined
13. ✅ Maximum module scale determined (50 nodes recommended)

**All NEEDS CLARIFICATION items resolved** ✅

---

## Phase 1: Design & Contracts

### Data Model

✅ **Complete** - See `data-model.md`

**Core Entities**: 7 entities defined with relationships
- Node (Device) - Bare metal server configuration
- Interface - Network interface configuration
- Category - Provisioning profile template
- SoftwareImage - OS image (pre-existing)
- Network - Network segment (pre-existing)
- PowerAction - IPMI power operation (ephemeral)
- NodeStatus - Current provisioning state (queried)

**Entity Relationships**:
- Node ↔ Category (Many-to-1)
- Node ↔ Network (Many-to-1)
- Node ↔ Interface (1-to-Many)
- Node ↔ PowerAction (1-to-1 ephemeral)
- Category ↔ SoftwareImage (Many-to-1)

**State Machine**: Node provisioning lifecycle from "Not Found" → "Registered" → "Provisioning" → "Active"

---

### API Contracts

✅ **Complete** - See `contracts/` directory

**Module Interface** (`contracts/module-interface.md`):
- Input variables: 15 variables (4 required, 11 optional)
- Output variables: 4 outputs (node_status, provisioning_summary, node_bmc_ips, device_ids)
- Provider requirements: Terraform >= 1.14, BCM provider ~> 0.1
- Example workflows: initial provisioning, re-provisioning, parallel provisioning

**Resource Schemas** (JSON Schema format):
- `device-schema.json` - bcm_cmdevice_device resource structure
- `category-schema.json` - bcm_cmdevice_category resource structure
- `power-action-schema.json` - bcm_cmdevice_power action structure

---

### Quick Start Guide

✅ **Complete** - See `quickstart.md`

**Sections**:
1. Prerequisites checklist (15 min) - 5 verification steps
2. Installation (5 min) - Clone repo, verify module files
3. Configuration (10 min) - Create root module, set variables
4. Initial provisioning (30 min) - Device creation, power-on, status verification
5. Verification (5 min) - SSH access, BMC registration, Terraform state
6. Troubleshooting - Common issues with solutions
7. Next steps - Re-provisioning, adding nodes, scaling

**Estimated Total Time**: 45 minutes (setup) + 30 minutes (first provisioning) = 75 minutes

---

### Agent Context Update

⏸️ **Deferred** - Agent context update will be performed after module implementation (Phase 2/3).

**Planned Update**:
- Add BCM provider resources and data sources to agent knowledge
- Document module patterns for provisioning workflows
- Add ipmitool fallback patterns for Terraform <1.14

**Script to Run** (after implementation):
```bash
.specify/scripts/bash/update-agent-context.sh copilot
```

---

## Constitution Check - Post-Design Re-evaluation

*Re-checking constitution compliance after Phase 1 design...*

### Design Alignment Review

**✅ Module-First Architecture**: Design creates reusable module with clear interface contract, promoting consumption pattern.

**✅ Specification-Driven Development**: All design decisions trace back to specification requirements (FR-001 to FR-052). Data model, contracts, and quickstart align with user stories.

**✅ Security-First Automation**:
- Sensitive variables for BMC credentials (bmc_username, bmc_password marked sensitive)
- JSON schemas enforce credential format validation
- Quickstart emphasizes environment variable usage over .tfvars files
- State encryption documented as requirement

**✅ File Organization**: Module structure follows Terraform best practices:
- Standard files: main.tf, data.tf, power.tf, variables.tf, outputs.tf, locals.tf, versions.tf, README.md
- Logical separation: power actions in dedicated power.tf, data sources in data.tf

**✅ Documentation Requirements**:
- README.md planned with prerequisites, usage, troubleshooting
- Quickstart.md provides step-by-step operator guidance
- Data model documents entity relationships
- Contracts define module interface

**✅ Variable Management**: 
- All variables have descriptions, types, validation blocks
- Sensitive variables marked appropriately
- Enum constraints implemented via validation blocks

**✅ Security Best Practices**:
- Credentials never hardcoded
- Sensitive outputs marked
- IPMI network isolation documented
- Security considerations section in contracts

### Post-Design Gates Status: **PASS ✅**

No violations introduced during design phase. All constitution principles maintained.

---

## Phase 2: Implementation Planning (Out of Scope)

**Note**: The `/speckit.plan` command ends after Phase 1 (Design & Contracts). Implementation planning and execution are handled by subsequent commands:

- **`/speckit.tasks`** - Generate tasks.md with implementation steps
- **`/speckit.implement`** - Execute implementation tasks

**Artifacts Ready for Implementation**:
1. ✅ research.md - All technical decisions documented
2. ✅ data-model.md - Entity relationships and state machine
3. ✅ contracts/ - Module interface and resource schemas
4. ✅ quickstart.md - Operator guide for first use

---

## Summary

### Phase 0: Research ✅ Complete
- 13 research tasks completed
- All NEEDS CLARIFICATION items resolved
- Consolidated findings in research.md (33,000 words)

### Phase 1: Design & Contracts ✅ Complete
- Data model with 7 entities and relationships
- Module interface contract with 15 inputs, 4 outputs
- 3 JSON schemas for resource validation
- Quick start guide with 7 sections
- Constitution compliance maintained

### Deliverables
| Artifact | Status | Lines | Purpose |
|----------|--------|-------|---------|
| plan.md | ✅ Complete | 500+ | This document |
| research.md | ✅ Complete | 1,200+ | Research findings |
| data-model.md | ✅ Complete | 800+ | Entity relationships |
| contracts/module-interface.md | ✅ Complete | 400+ | Module API |
| contracts/device-schema.json | ✅ Complete | 120+ | Device resource schema |
| contracts/category-schema.json | ✅ Complete | 100+ | Category resource schema |
| contracts/power-action-schema.json | ✅ Complete | 40+ | Power action schema |
| quickstart.md | ✅ Complete | 400+ | Operator quick start |

### Next Steps
1. **Generate tasks.md**: Run `/speckit.tasks` to create implementation task list
2. **Review & approval**: Platform team reviews plan and design artifacts
3. **Implementation**: Execute `/speckit.implement` or manual implementation
4. **Testing**: Follow quickstart.md for manual validation
5. **Documentation**: Update README.md with usage examples
6. **Deployment**: Merge to dev branch after testing

---

## Appendix: Key Design Decisions Summary

| Decision Point | Choice | Rationale |
|----------------|--------|-----------|
| **Terraform Actions** | Use bcm_cmdevice_power (1.14+) with null_resource fallback | Native integration, backward compatibility |
| **Data Source Filtering** | Client-side via locals | BCM provider lacks native filter blocks |
| **Power Action Opt-in** | enable_power_action boolean + explicit power_action value | Prevents accidental reboots |
| **Provisioning Mode** | Conditional depends_on chains (sequential) vs for_each (parallel) | Operator control, BCM handles slot limits |
| **Category Management** | Optional creation via create_custom_category flag | Flexibility for existing vs custom categories |
| **Interface Configuration** | Flexible interfaces list with single bootable flag | Supports multi-homed nodes, explicit PXE interface |
| **Status Querying** | Post-action data source query with depends_on | Immediate feedback, no polling overhead |
| **Testing Strategy** | Manual validation, defer automated framework | Bare metal provisioning not easily mocked |
| **State Locking** | Backend-provided (HCP Terraform recommended) | Not a module concern |
| **Multi-Cluster** | Single instance per cluster, separate workspaces | Clear isolation, simple model |
| **Max Scale** | 50 nodes per instance recommended | Performance, provisioning time, operator experience |

---

**Plan Status**: ✅ Complete  
**Ready for**: `/speckit.tasks` command  
**Branch**: `001-bcm-node-provisioning`  
**Generated**: 2025-01-10
