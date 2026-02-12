# Tasks: BCM Node Provisioning Module

**Input**: Design documents from `/specs/001-bcm-node-provisioning/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ ✅, quickstart.md ✅

**Tests**: NOT REQUESTED - Test tasks omitted per specification analysis

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `- [ ] [ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions

This is a Terraform child module. All paths are relative to module directory:
- Module directory: `bcm_node_provisioning/`
- Module files: `main.tf`, `data.tf`, `power.tf`, `variables.tf`, `outputs.tf`, `locals.tf`, `versions.tf`, `README.md`

---

## Phase 1: Setup (Module Structure)

**Purpose**: Create the Terraform child module structure and foundational files

- [ ] T001 Create module directory `bcm_node_provisioning/` at repository root
- [ ] T002 [P] Create `bcm_node_provisioning/versions.tf` with Terraform >= 1.14 and BCM provider ~> 0.1 constraints
- [ ] T003 [P] Create `bcm_node_provisioning/variables.tf` with placeholder for input variable declarations
- [ ] T004 [P] Create `bcm_node_provisioning/outputs.tf` with placeholder for output declarations
- [ ] T005 [P] Create `bcm_node_provisioning/locals.tf` with placeholder for computed values
- [ ] T006 [P] Create `bcm_node_provisioning/data.tf` with placeholder for data sources
- [ ] T007 [P] Create `bcm_node_provisioning/main.tf` with placeholder for device resources
- [ ] T008 [P] Create `bcm_node_provisioning/power.tf` with placeholder for power actions
- [ ] T009 [P] Create `bcm_node_provisioning/README.md` with module purpose and placeholder sections

---

## Phase 2: Foundational (Core Data Sources & Variables)

**Purpose**: Core infrastructure that MUST be complete before ANY user story can be implemented

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T010 [P] Define `software_image_name` variable in `bcm_node_provisioning/variables.tf` with validation
- [ ] T011 [P] Define `management_network` variable in `bcm_node_provisioning/variables.tf` with description
- [ ] T012 [P] Define `oob_network` variable in `bcm_node_provisioning/variables.tf` with default "oob-mgmt"
- [ ] T013 [P] Define `bmc_username` sensitive variable in `bcm_node_provisioning/variables.tf`
- [ ] T014 [P] Define `bmc_password` sensitive variable in `bcm_node_provisioning/variables.tf`
- [ ] T015 Implement `data.bcm_cmpart_softwareimages` lookup in `bcm_node_provisioning/data.tf`
- [ ] T016 [P] Implement `data.bcm_cmnet_networks` lookup in `bcm_node_provisioning/data.tf`
- [ ] T017 Add `software_image_uuid` local in `bcm_node_provisioning/locals.tf` with client-side filter by name
- [ ] T018 [P] Add `management_network_id` local in `bcm_node_provisioning/locals.tf` with client-side filter
- [ ] T019 [P] Add `oob_network_id` local in `bcm_node_provisioning/locals.tf` with client-side filter
- [ ] T020 [P] Add validation error handling for missing software image in `bcm_node_provisioning/locals.tf`
- [ ] T021 [P] Add validation error handling for missing networks in `bcm_node_provisioning/locals.tf`

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Initial Bare Metal Node Provisioning (Priority: P1) 🎯 MVP

**Goal**: Provision brand new bare metal nodes from powered-off state to fully operational with correct OS image

**Independent Test**: Provision a single new node (e.g., dgx-05) from powered-off state to OS-booted operational state

### Implementation for User Story 1

- [ ] T022 [P] [US1] Define `nodes` variable (map of objects) in `bcm_node_provisioning/variables.tf` with required attributes: mac (string), bmc_mac (string), ipmi_ip (string), category (string), management_ip (string), interfaces (map of objects), roles (list of strings) per FR-005, with validation for required fields and type constraints
- [ ] T023 [P] [US1] Define `enable_power_action` boolean variable in `bcm_node_provisioning/variables.tf` with default false
- [ ] T024 [P] [US1] Define `power_action` variable in `bcm_node_provisioning/variables.tf` with validation (power_on/power_off/power_cycle/power_reset)
- [ ] T025 [US1] Implement `bcm_cmdevice_device` resource in `bcm_node_provisioning/main.tf` with for_each over var.nodes
- [ ] T026 [US1] Configure device hostname, mac, category attributes in `bcm_node_provisioning/main.tf` device resource
- [ ] T027 [US1] Configure device management_network reference in `bcm_node_provisioning/main.tf` using local.management_network_id
- [ ] T028 [US1] Configure device power_control = "ipmi" in `bcm_node_provisioning/main.tf`
- [ ] T029 [US1] Configure device bmc_settings block in `bcm_node_provisioning/main.tf` with username, password, privilege
- [ ] T030 [US1] Configure device interfaces list in `bcm_node_provisioning/main.tf` with physical eth0 and bmc interfaces
- [ ] T031 [US1] Set bootable = true for eth0 interface in `bcm_node_provisioning/main.tf` device interfaces
- [ ] T032 [US1] Configure device roles list in `bcm_node_provisioning/main.tf` from var.nodes[*].roles
- [ ] T033 [US1] Implement `bcm_cmdevice_power` action resource in `bcm_node_provisioning/power.tf` with conditional for_each
- [ ] T034 [US1] Configure power action device_id reference in `bcm_node_provisioning/power.tf` to bcm_cmdevice_device resources
- [ ] T035 [US1] Configure power action power_action attribute in `bcm_node_provisioning/power.tf` from var.power_action
- [ ] T036 [US1] Configure power action wait_for_completion = true in `bcm_node_provisioning/power.tf`
- [ ] T037 [US1] Configure power action timeout = 600 in `bcm_node_provisioning/power.tf`
- [ ] T038 [US1] Add depends_on for device resources in `bcm_node_provisioning/power.tf` power action
- [ ] T039 [US1] Implement `data.bcm_cmdevice_nodes` query in `bcm_node_provisioning/data.tf` with depends_on power actions
- [ ] T040 [US1] Add `node_status` local in `bcm_node_provisioning/locals.tf` mapping hostnames to state/ip/success
- [ ] T041 [P] [US1] Define `node_status` output in `bcm_node_provisioning/outputs.tf` with success/failed/not_found indicators
- [ ] T042 [P] [US1] Define `device_ids` output in `bcm_node_provisioning/outputs.tf` with device resource IDs
- [ ] T043 [P] [US1] Define `node_bmc_ips` output in `bcm_node_provisioning/outputs.tf` for operational reference
- [ ] T044 [US1] Add variable validation for duplicate hostnames in `bcm_node_provisioning/variables.tf` nodes variable
- [ ] T045 [US1] Add variable validation for duplicate MAC addresses in `bcm_node_provisioning/variables.tf` nodes variable
- [ ] T046 [US1] Document initial provisioning workflow in `bcm_node_provisioning/README.md` Usage section
- [ ] T047 [US1] Document prerequisites checklist in `bcm_node_provisioning/README.md` Prerequisites section (10 items from FR-041 to FR-050)
- [ ] T048 [US1] Add example configuration for 2 DGX nodes in `bcm_node_provisioning/README.md` Examples section

**Checkpoint**: At this point, User Story 1 should be fully functional - single node provisioning from powered-off to active

---

## Phase 4: User Story 2 - Node Re-provisioning with Image Updates (Priority: P2)

**Goal**: Re-provision existing operational nodes with updated OS images while preserving node identity

**Independent Test**: Re-provision a previously-provisioned node with a different OS image and verify new image boots

### Implementation for User Story 2

- [ ] T049 [P] [US2] Define `provisioning_summary` output in `bcm_node_provisioning/outputs.tf` with per-node success/failure counts
- [ ] T050 [US2] Add lifecycle ignore_changes for device resources in `bcm_node_provisioning/main.tf` to prevent unwanted recreates
- [ ] T051 [US2] Document re-provisioning workflow in `bcm_node_provisioning/README.md` Re-provisioning section
- [ ] T052 [US2] Add example for power_cycle action in `bcm_node_provisioning/README.md` with image change scenario
- [ ] T053 [US2] Add troubleshooting guide for re-provisioning failures in `bcm_node_provisioning/README.md`
- [ ] T054 [US2] Add note about workload safety checks in `bcm_node_provisioning/README.md` (operator responsibility)
- [ ] T055 [US2] Document node identity preservation in `bcm_node_provisioning/README.md` (hostname, MAC, IP remain same)

**Checkpoint**: At this point, User Stories 1 AND 2 should both work - new provisioning and re-provisioning

---

## Phase 5: User Story 3 - Category Management with Custom Configuration (Priority: P3)

**Goal**: Create and manage custom provisioning categories with specific installation behaviors for different node roles

**Independent Test**: Create custom category with specific disk setup and kernel parameters, provision a node, verify custom settings applied

### Implementation for User Story 3

- [ ] T056 [P] [US3] Define `create_custom_category` boolean variable in `bcm_node_provisioning/variables.tf` with default false
- [ ] T057 [P] [US3] Define `custom_category_name` variable in `bcm_node_provisioning/variables.tf`
- [ ] T058 [P] [US3] Define `install_mode` variable in `bcm_node_provisioning/variables.tf` with validation (AUTO/FULL/MINIMAL)
- [ ] T059 [P] [US3] Define `kernel_parameters` variable in `bcm_node_provisioning/variables.tf` for custom kernel options
- [ ] T060 [P] [US3] Define `boot_loader` variable in `bcm_node_provisioning/variables.tf` with default "grub2"
- [ ] T061 [P] [US3] Define `disksetup_xml_path` variable in `bcm_node_provisioning/variables.tf` for custom disk layouts
- [ ] T062 [P] [US3] Define `initialize_scripts` list variable in `bcm_node_provisioning/variables.tf` for pre-install hooks
- [ ] T063 [P] [US3] Define `finalize_scripts` list variable in `bcm_node_provisioning/variables.tf` for post-install hooks
- [ ] T064 [P] [US3] Define `gpu_settings` object variable in `bcm_node_provisioning/variables.tf` for DGX-specific config
- [ ] T065 [US3] Implement `data.bcm_cmdevice_categories` lookup in `bcm_node_provisioning/data.tf` for existing categories
- [ ] T066 [US3] Implement `bcm_cmdevice_category` resource in `bcm_node_provisioning/main.tf` with conditional count
- [ ] T067 [US3] Configure category name and software_image_proxy in `bcm_node_provisioning/main.tf` category resource
- [ ] T068 [US3] Configure category install_mode in `bcm_node_provisioning/main.tf` from variable
- [ ] T069 [US3] Configure category bmc_settings in `bcm_node_provisioning/main.tf` with credentials
- [ ] T070 [US3] Configure category disksetup from file() in `bcm_node_provisioning/main.tf` if xml path provided
- [ ] T071 [US3] Configure category initialize scripts in `bcm_node_provisioning/main.tf` from variable
- [ ] T072 [US3] Configure category finalize scripts in `bcm_node_provisioning/main.tf` from variable
- [ ] T073 [US3] Configure category kernel_parameters in `bcm_node_provisioning/main.tf` from variable
- [ ] T074 [US3] Configure category boot_loader in `bcm_node_provisioning/main.tf` from variable
- [ ] T075 [US3] Configure category gpu_settings in `bcm_node_provisioning/main.tf` if provided
- [ ] T076 [US3] Add `category_id` local in `bcm_node_provisioning/locals.tf` choosing custom vs existing category
- [ ] T077 [US3] Document category creation workflow in `bcm_node_provisioning/README.md` Custom Categories section
- [ ] T078 [US3] Add example GPU worker category with nvidia kernel params in `bcm_node_provisioning/README.md`
- [ ] T079 [US3] Add example control plane category with different disk layout in `bcm_node_provisioning/README.md`
- [ ] T080 [US3] Document disksetup XML format and location in `bcm_node_provisioning/README.md`

**Checkpoint**: All three user stories should now work - new provisioning, re-provisioning, and custom categories

---

## Phase 6: User Story 4 - Parallel Provisioning with Slot Management (Priority: P3)

**Goal**: Provision multiple nodes simultaneously to reduce deployment time while respecting BCM slot limits

**Independent Test**: Provision 10 nodes with parallel mode and verify all provision concurrently within slot limits

### Implementation for User Story 4

- [ ] T081 [P] [US4] Define `provisioning_mode` variable in `bcm_node_provisioning/variables.tf` with validation (sequential/parallel)
- [ ] T082 [P] [US4] Define `node_execution_order` list variable in `bcm_node_provisioning/variables.tf` for sequential mode
- [ ] T083 [US4] Add `ordered_node_keys` local in `bcm_node_provisioning/locals.tf` based on provisioning_mode
- [ ] T084 [US4] Implement sequential depends_on chain logic in `bcm_node_provisioning/power.tf` for sequential mode
- [ ] T085 [US4] Add conditional depends_on in `bcm_node_provisioning/power.tf` using dynamic block or count index logic
- [ ] T086 [US4] Document parallel provisioning in `bcm_node_provisioning/README.md` Parallel Provisioning section
- [ ] T087 [US4] Document sequential provisioning in `bcm_node_provisioning/README.md` Sequential Provisioning section
- [ ] T088 [US4] Add example for 20-node deployment with slot management in `bcm_node_provisioning/README.md`
- [ ] T089 [US4] Document BCM slot limit configuration in `bcm_node_provisioning/README.md` (MaxNumberOfProvisioningThreads)
- [ ] T090 [US4] Add troubleshooting for provisioning queue delays in `bcm_node_provisioning/README.md`

**Checkpoint**: All four user stories complete - full module functionality delivered

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories and finalize the module

- [ ] T091 [P] Add module description and purpose in `bcm_node_provisioning/README.md` Introduction section
- [ ] T092 [P] Document all input variables with types and defaults in `bcm_node_provisioning/README.md` Inputs section
- [ ] T093 [P] Document all outputs with descriptions in `bcm_node_provisioning/README.md` Outputs section
- [ ] T094 [P] Add prerequisites verification commands in `bcm_node_provisioning/README.md` (cmsh commands from quickstart.md)
- [ ] T095 [P] Add security considerations section in `bcm_node_provisioning/README.md` (sensitive vars, state encryption, IPMI isolation)
- [ ] T096 [P] Add limitations section in `bcm_node_provisioning/README.md` (50 node max, Terraform 1.14+ requirement)
- [ ] T097 [P] Add troubleshooting section in `bcm_node_provisioning/README.md` (BMC unreachable, image not found, MAC conflicts)
- [ ] T098 Add ipmitool fallback implementation in `bcm_node_provisioning/power.tf` using null_resource for Terraform < 1.14
- [ ] T099 Add conditional logic in `bcm_node_provisioning/power.tf` to choose bcm_cmdevice_power vs ipmitool based on TF version check
- [ ] T100 Add version detection local in `bcm_node_provisioning/locals.tf` for Terraform version >= 1.14 check
- [ ] T101 [P] Document ipmitool fallback in `bcm_node_provisioning/README.md` Compatibility section
- [ ] T102 Run `terraform fmt` on all module files in `bcm_node_provisioning/`
- [ ] T103 Run `terraform validate` on module in `bcm_node_provisioning/`
- [ ] T104 Create root module example in repository root demonstrating module usage
- [ ] T105 Run quickstart.md validation (manual test with 2 nodes)
- [ ] T106 Update repository root README.md with link to new module

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion - BLOCKS all user stories
- **User Stories (Phase 3-6)**: All depend on Foundational phase completion
  - US1 (Phase 3): MVP - must complete first
  - US2 (Phase 4): Depends on US1 (re-provision requires initial provision capability)
  - US3 (Phase 5): Can start after US1, independent of US2
  - US4 (Phase 6): Can start after US1, independent of US2/US3
- **Polish (Phase 7)**: Depends on all desired user stories being complete

### User Story Dependencies

- **User Story 1 (P1)**: Can start after Foundational (Phase 2) - No dependencies on other stories ✅ MVP
- **User Story 2 (P2)**: Requires US1 complete (cannot re-provision without initial provision)
- **User Story 3 (P3)**: Can start after US1 complete, independent of US2 (custom categories work for initial provision)
- **User Story 4 (P3)**: Can start after US1 complete, independent of US2/US3 (parallel mode works for any provisioning)

### Within Each User Story

- Variables before resource implementation
- Data sources before locals that filter them
- Locals before resources that reference them
- Resources before outputs that reference them
- Core implementation before documentation

### Parallel Opportunities

**Phase 1 (Setup)**: T002, T003, T004, T005, T006, T007, T008, T009 can run in parallel (all create different files)

**Phase 2 (Foundational)**: T010-T014 can run in parallel (different variables), T016-T021 can run in parallel (different locals/data sources after T015)

**Phase 3 (US1)**: T022-T024 can run in parallel (different variables), T041-T043 can run in parallel (different outputs)

**Phase 5 (US3)**: T056-T064 can run in parallel (different variables), T081-T082 can run in parallel (different variables)

**Phase 7 (Polish)**: T091-T097 and T101 can run in parallel (different README sections), T102-T103 can run sequentially

---

## Parallel Example: User Story 1 Core Variables

```bash
# Launch all core variables for User Story 1 together:
@task T022: Define nodes variable in bcm_node_provisioning/variables.tf
@task T023: Define enable_power_action variable in bcm_node_provisioning/variables.tf
@task T024: Define power_action variable in bcm_node_provisioning/variables.tf
```

---

## Parallel Example: User Story 1 Outputs

```bash
# Launch all outputs for User Story 1 together:
@task T041: Define node_status output in bcm_node_provisioning/outputs.tf
@task T042: Define device_ids output in bcm_node_provisioning/outputs.tf
@task T043: Define node_bmc_ips output in bcm_node_provisioning/outputs.tf
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T009)
2. Complete Phase 2: Foundational (T010-T021) - CRITICAL - blocks all stories
3. Complete Phase 3: User Story 1 (T022-T048)
4. **STOP and VALIDATE**: Test User Story 1 independently with quickstart.md
5. Deploy/demo MVP - single node provisioning works!

### Incremental Delivery

1. Complete Setup + Foundational (Phases 1-2) → Foundation ready
2. Add User Story 1 (Phase 3) → Test independently → Deploy/Demo (MVP! 🎯)
3. Add User Story 2 (Phase 4) → Test independently → Deploy/Demo (Re-provisioning works!)
4. Add User Story 3 (Phase 5) → Test independently → Deploy/Demo (Custom categories work!)
5. Add User Story 4 (Phase 6) → Test independently → Deploy/Demo (Parallel provisioning works!)
6. Complete Polish (Phase 7) → Production-ready module
7. Each story adds value without breaking previous stories

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (Phases 1-2)
2. Team completes User Story 1 together (Phase 3) - MVP must work first
3. Once US1 is validated:
   - Developer A: User Story 2 (re-provisioning)
   - Developer B: User Story 3 (custom categories)
   - Developer C: User Story 4 (parallel provisioning)
4. Stories complete and integrate independently

---

## Summary

**Total Tasks**: 106 tasks across 7 phases

**Task Breakdown by Phase**:
- Phase 1 (Setup): 9 tasks
- Phase 2 (Foundational): 12 tasks
- Phase 3 (User Story 1 - Initial Provisioning): 27 tasks 🎯 MVP
- Phase 4 (User Story 2 - Re-provisioning): 7 tasks
- Phase 5 (User Story 3 - Custom Categories): 25 tasks
- Phase 6 (User Story 4 - Parallel Provisioning): 10 tasks
- Phase 7 (Polish): 16 tasks

**Parallel Task Count**: 54 tasks marked [P] can run in parallel with other tasks

**Independent Test Criteria**:
- US1: Provision single new node from powered-off to active state
- US2: Re-provision existing node with different image, verify new OS boots
- US3: Create custom category, provision node, verify custom settings applied
- US4: Provision 10 nodes in parallel, verify concurrent provisioning within limits

**MVP Scope**: Phases 1-3 only (48 tasks) - delivers initial bare metal provisioning capability

**Module Files Created**:
- `bcm_node_provisioning/versions.tf` - Provider constraints
- `bcm_node_provisioning/variables.tf` - ~20 input variables
- `bcm_node_provisioning/outputs.tf` - ~5 outputs
- `bcm_node_provisioning/locals.tf` - Computed values and filters
- `bcm_node_provisioning/data.tf` - Data sources (images, networks, categories, nodes)
- `bcm_node_provisioning/main.tf` - Device and category resources
- `bcm_node_provisioning/power.tf` - Power actions (IPMI control)
- `bcm_node_provisioning/README.md` - Complete module documentation

---

## Format Validation ✅

All 106 tasks follow the required checklist format:
- ✅ All tasks start with `- [ ]` (markdown checkbox)
- ✅ All tasks have sequential Task ID (T001-T106)
- ✅ All parallelizable tasks marked with [P]
- ✅ All user story tasks marked with [US1], [US2], [US3], or [US4]
- ✅ All tasks include exact file paths in description
- ✅ Setup and Foundational phases have NO story labels (correct)
- ✅ Polish phase has NO story labels (correct)

---

## Notes

- **Tests omitted**: No test tasks included as tests were not requested in specification
- **Module pattern**: This is a Terraform child module, not typical src/ structure
- **User story independence**: Each story can be tested independently per spec requirements
- **Power actions opt-in**: Power actions are explicit via variables, not auto-triggered
- **Security first**: BMC credentials are sensitive variables throughout
- **Terraform 1.14+ required**: Actions feature required, ipmitool fallback for older versions
- **BCM provider**: All resources/data sources use hashi-demo-lab/bcm provider
- **Validation**: Each user story has clear independent test criteria from spec.md
