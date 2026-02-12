# Feature Specification: BCM Node Provisioning Module

**Feature Branch**: `001-bcm-node-provisioning`  
**Created**: 2025-01-10  
**Status**: Draft  
**Input**: User description: "Create a feature specification for a new BCM Node Provisioning module (`bcm_node_provisioning/`) that automates bare metal node provisioning and re-provisioning via the BCM API using IPMI/PXE boot."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Initial Bare Metal Node Provisioning (Priority: P1)

Infrastructure operators need to provision brand new DGX/CPU bare metal nodes from a clean state into a fully operational cluster member with the correct OS image and configuration. The operator defines node identity (hostname, MAC, BMC IP), assigns a software image category, and triggers PXE boot via IPMI power-on, with BCM handling all provisioning orchestration automatically.

**Why this priority**: This is the foundational capability - without the ability to provision new nodes, the module has no value. This is the minimum viable product that delivers immediate operational value.

**Independent Test**: Can be fully tested by provisioning a single new bare metal node from powered-off state to OS-booted state and delivers a functioning cluster node ready for workload deployment.

**Acceptance Scenarios**:

1. **Given** a bare metal node is powered off and has never been provisioned, **When** operator applies Terraform configuration with node identity and software image category, **Then** BCM creates device record with correct hostname, MAC address, category, BMC settings, and network interfaces
2. **Given** BCM device record exists for a new node, **When** operator triggers IPMI power_on action, **Then** node boots via PXE, downloads assigned OS image, completes installation, and reaches operational state
3. **Given** multiple new nodes are defined with provisioning_mode set to sequential, **When** provisioning is triggered, **Then** nodes provision one after another in defined order without exceeding provisioning slot limits
4. **Given** a node has finished provisioning successfully, **When** operator queries node status via Terraform outputs, **Then** node state shows as active/operational with correct hostname and IP assignments

---

### User Story 2 - Node Re-provisioning with Image Updates (Priority: P2)

Infrastructure operators need to re-provision existing operational nodes with updated OS images (security patches, version upgrades, configuration changes) without manual intervention. The operator updates the software image category assignment and triggers IPMI power_cycle to force a complete re-image while preserving node identity.

**Why this priority**: Re-provisioning is critical for production lifecycle management (patching, upgrades, disaster recovery) but requires initial provisioning to exist first. This extends the MVP to handle ongoing operations.

**Independent Test**: Can be fully tested by re-provisioning a single previously-provisioned node with a different OS image and verifying the node boots with the new image while maintaining its identity.

**Acceptance Scenarios**:

1. **Given** a node is currently operational with OS image A, **When** operator changes software_image_name to image B and triggers power_cycle, **Then** node reboots, re-provisions via PXE with new image, and completes installation with updated OS
2. **Given** multiple nodes require re-provisioning simultaneously, **When** provisioning_mode is set to parallel, **Then** all nodes re-provision concurrently up to the provisioning slot limit
3. **Given** a node is re-provisioning, **When** BCM reports provisioning status, **Then** operator can observe progress through Terraform outputs showing current provisioning phase
4. **Given** re-provisioning completes successfully, **When** operator verifies node state, **Then** node identity (hostname, IP, BMC settings) remains unchanged but OS version matches new image

---

### User Story 3 - Category Management with Custom Configuration (Priority: P3)

Infrastructure operators need to create and manage custom provisioning categories that define specific installation behaviors beyond just OS image selection. Categories include install mode (AUTO/FULL/MINIMAL), BMC settings, disk setup configurations, kernel parameters, boot loader settings, filesystem mounts, initialization scripts, and finalization scripts to support different node roles (GPU workers vs CPU control plane).

**Why this priority**: While important for production flexibility, basic provisioning can work with default categories. This enables advanced customization for complex deployment scenarios.

**Independent Test**: Can be fully tested by creating a custom category with specific disk setup and kernel parameters, provisioning a node with that category, and verifying the node reflects all custom settings post-provisioning.

**Acceptance Scenarios**:

1. **Given** operator needs DGX nodes with specific GPU kernel parameters, **When** operator defines category with custom kernel_parameters, **Then** provisioned DGX nodes boot with specified kernel configuration
2. **Given** different node roles require different disk layouts, **When** operator creates categories with role-specific disksetup configurations, **Then** provisioned nodes reflect correct disk partitioning based on assigned category
3. **Given** post-install configuration is required, **When** operator defines initialize and finalize scripts in category, **Then** scripts execute during provisioning lifecycle at correct phases
4. **Given** category references a software_image_proxy, **When** nodes are assigned to that category, **Then** all nodes in category automatically receive the linked OS image without individual configuration

---

### User Story 4 - Parallel Provisioning with Slot Management (Priority: P3)

Infrastructure operators need to provision multiple nodes simultaneously to reduce total deployment time for large clusters, while respecting BCM provisioning slot limits to avoid overloading the headnode provisioning service.

**Why this priority**: Efficiency enhancement that matters for large-scale deployments but not critical for basic functionality. Can be addressed after core provisioning works.

**Independent Test**: Can be fully tested by provisioning 10 nodes with provisioning_mode set to parallel and verifying all nodes provision concurrently within slot limits.

**Acceptance Scenarios**:

1. **Given** 20 nodes need provisioning and provisioning slot limit is 10, **When** provisioning_mode is parallel, **Then** first 10 nodes provision concurrently, next 10 queue and provision as slots become available
2. **Given** operator sets provisioning_mode to sequential, **When** provisioning starts, **Then** nodes provision one at a time in defined order regardless of slot availability
3. **Given** parallel provisioning is in progress, **When** one node fails, **Then** remaining nodes continue provisioning without interruption
4. **Given** provisioning completes for all nodes, **When** operator checks Terraform outputs, **Then** output shows completion status for each node with success/failure indication

---

### Edge Cases

- What happens when a node's BMC is unreachable during IPMI power action? System should fail gracefully with clear error indicating BMC connectivity issue and node identity.
- What happens when software image name doesn't exist on BCM headnode? Data source lookup should fail during Terraform plan with clear error before any resources are created.
- What happens when provisioning slot limit is reached? BCM queues additional nodes; module should respect slot limits and provision in batches according to provisioning_mode.
- What happens when a node MAC address conflicts with existing BCM device record? BCM should reject device creation; Terraform should surface the conflict error clearly.
- What happens when network name referenced in management_network variable doesn't exist? Data source lookup should fail during plan phase before any device creation.
- What happens when a node fails to PXE boot (hardware failure, network issue)? BCM provisioning times out; node status shows as failed; operator can inspect logs and retry power action.
- What happens when BMC credentials are incorrect? IPMI power action fails with authentication error; Terraform surfaces error to operator for credential correction.
- What happens when multiple nodes have the same hostname? BCM should reject duplicate hostnames; Terraform validation should catch this during plan phase.
- What happens when re-provisioning a node that is currently running critical workloads? Module does not prevent power_cycle; operator must ensure workload safety before triggering re-provisioning (documented in README as prerequisite).
- What happens when operator runs terraform apply twice without changing configuration? Terraform should detect no changes needed; no power actions triggered (power actions are explicit via power_action variable).

## Requirements *(mandatory)*

### Functional Requirements

#### Module Structure & Organization

- **FR-001**: Module MUST be organized as a reusable Terraform child module in directory `bcm_node_provisioning/` with standard structure: main.tf, variables.tf, outputs.tf, data.tf, power.tf, locals.tf, versions.tf, README.md
- **FR-002**: Module MUST declare provider version constraint for `hashi-demo-lab/bcm` provider version ~> 0.1
- **FR-003**: Module MUST declare Terraform version requirement of >= 1.14 to support Actions feature for power actions
- **FR-004**: Module README.md MUST document all documented prerequisites without attempting to validate them

#### Node Identity & Device Management

- **FR-005**: Module MUST accept a `nodes` variable as map(object) where each key is hostname and value contains: mac (string), category (string), management_ip (string), ipmi_ip (string), interfaces (map), roles (list)
- **FR-006**: Module MUST create `bcm_cmdevice_device` resources for each node in nodes map with hostname, MAC address, category assignment, network interfaces, BMC settings, and `power_control = "ipmi"`
- **FR-007**: Module MUST assign each node to specified category via category attribute in device resource
- **FR-008**: Module MUST configure BMC settings for each device including BMC username and password from sensitive variables
- **FR-009**: Module MUST configure network interfaces for each node based on interfaces map in node configuration
- **FR-010**: Module MUST support assigning roles to nodes via roles list attribute

#### Software Image & Category Management

- **FR-011**: Module MUST use data source `data.bcm_cmpart_softwareimages` to look up existing software image by name from `software_image_name` variable
- **FR-012**: Module MUST fail during plan phase if specified software image does not exist on BCM headnode
- **FR-013**: Module MUST use data source `data.bcm_cmdevice_categories` to look up existing categories
- **FR-014**: Module MUST support creating or referencing `bcm_cmdevice_category` resources with attributes: name, software_image_proxy, install_mode, bmc_settings, disksetup, initialize scripts, finalize scripts, kernel_parameters, boot_loader, fsmounts, modules
- **FR-015**: Module MUST link categories to software images via `software_image_proxy` attribute containing software image ID from data source lookup
- **FR-016**: Module MUST accept `install_mode` variable with allowed values: "AUTO", "FULL", "MINIMAL"

#### Network Configuration

- **FR-017**: Module MUST use data source `data.bcm_cmnet_networks` to look up networks by name
- **FR-018**: Module MUST accept `management_network` variable for PXE/management network name
- **FR-019**: Module MUST fail during plan phase if specified network names do not exist

#### Power Management & Provisioning

- **FR-020**: Module MUST use `bcm_cmdevice_power` resource (Terraform Actions feature) to trigger IPMI power actions
- **FR-021**: Module MUST accept `power_action` variable with allowed values: "power_on" (for new provisioning) or "power_cycle" (for re-provisioning)
- **FR-022**: Module MUST support explicit opt-in for power actions via variable (not auto-triggered on every plan/apply)
- **FR-023**: Module MUST accept `provisioning_mode` variable with allowed values: "sequential" or "parallel"
- **FR-024**: Module MUST provision nodes sequentially (one at a time) when provisioning_mode is "sequential"
- **FR-025**: Module MUST provision nodes concurrently (up to slot limit) when provisioning_mode is "parallel"
- **FR-026**: Power actions MUST be idempotent - multiple applies with same configuration should not trigger repeated power cycles

#### Node Status & Monitoring

- **FR-027**: Module MUST use data source `data.bcm_cmdevice_nodes` to query node state after provisioning
- **FR-028**: Module MUST output node provisioning status for each node including hostname, state, IP assignments, and success/failure indication
- **FR-029**: Module MUST output node BMC IP addresses for operational reference
- **FR-030**: Module MUST output category assignments for each node

#### Security & Credentials

- **FR-031**: Module MUST accept BMC credentials via sensitive variables `bmc_username` and `bmc_password`
- **FR-032**: Module MUST mark all credential variables as sensitive to prevent console/log exposure
- **FR-033**: Module MUST NOT hardcode any credentials in configuration files
- **FR-034**: Module MUST document IPMI traffic isolation to OOB management network in README

#### Variable Validation & Defaults

- **FR-035**: Module MUST validate that hostnames in nodes map are unique
- **FR-036**: Module MUST validate that MAC addresses in nodes map are unique
- **FR-037**: Module MUST validate power_action contains only allowed values
- **FR-038**: Module MUST validate provisioning_mode contains only allowed values
- **FR-039**: Module MUST validate install_mode contains only allowed values
- **FR-040**: Module MUST provide reasonable defaults for optional variables

#### Documentation & Prerequisites

- **FR-041**: Module README MUST document prerequisite: BCM 10 installed on headnode with management network, DNS, IP ranges configured
- **FR-042**: Module README MUST document prerequisite: Software image prepared/imported on BCM headnode
- **FR-043**: Module README MUST document prerequisite: Headnode DHCP/TFTP/PXE server active
- **FR-044**: Module README MUST document prerequisite: Headnode Certificate Authority functioning
- **FR-045**: Module README MUST document prerequisite: Provisioning role active on headnode with localimages including target image
- **FR-046**: Module README MUST document prerequisite: Provisioning slots ≥ number of target nodes (default: 10)
- **FR-047**: Module README MUST document prerequisite: `DeviceResolveAnyMAC=1` in `/cm/local/apps/cmd/etc/cmd.conf`
- **FR-048**: Module README MUST document prerequisite: `MaxNumberOfProvisioningThreads` adequate in `/etc/cmd.conf`
- **FR-049**: Module README MUST document prerequisite: `updateprovisioners` run after any image changes
- **FR-050**: Module README MUST document prerequisite: BMC/IPMI network connectivity from headnode to node BMC interfaces
- **FR-051**: Module README MUST include example usage for both new provisioning (power_on) and re-provisioning (power_cycle) scenarios
- **FR-052**: Module README MUST document expected project context: Provider hashi-demo-lab/bcm ~> 0.1, control plane nodes, GPU workers, network ranges

### Key Entities *(include if feature involves data)*

- **Node**: Represents a bare metal server (DGX or CPU) with attributes: hostname (unique identifier), MAC address (physical identity), BMC/IPMI IP (out-of-band management), management IP (in-band network), roles (functionality designation: control plane, worker, GPU), category (provisioning profile), interfaces (network configuration), power state (on/off/cycling)

- **Category**: Represents a provisioning profile template with attributes: name (unique identifier), software_image_proxy (reference to OS image), install_mode (installation behavior: AUTO/FULL/MINIMAL), bmc_settings (BMC configuration), disksetup (partition layout), initialize scripts (pre-install hooks), finalize scripts (post-install hooks), kernel_parameters (boot parameters), boot_loader (bootloader config), fsmounts (filesystem mounts), modules (kernel modules). Categories define how nodes are provisioned and link nodes to software images.

- **Software Image**: Represents an OS image stored on BCM headnode with attributes: name (unique identifier), image ID (BCM internal reference), version (OS version), path (storage location on headnode). Images are pre-existing artifacts managed outside Terraform, referenced via data source lookup.

- **Network**: Represents a network segment with attributes: name (unique identifier), CIDR range (address space), purpose (management/production/OOB), DHCP range (dynamic allocation pool). Networks define where nodes are connected for PXE boot and operational communication.

- **BMC Credentials**: Represents authentication for out-of-band management with attributes: username (BMC login), password (sensitive credential). Credentials enable IPMI power control and console access.

- **Power Action**: Represents an IPMI command with attributes: action type (power_on/power_off/reboot/power_cycle), target node (hostname), execution state (pending/running/complete/failed). Power actions trigger physical state changes on bare metal hardware.

- **Provisioning Slot**: Represents a concurrency unit on BCM headnode with attributes: slot count (total available), slots in use (currently provisioning), slot limit (maximum concurrent). Slots constrain parallel provisioning to prevent headnode resource exhaustion.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can provision a single new bare metal node from powered-off state to OS-booted operational state in under 30 minutes without manual intervention beyond initial Terraform apply
- **SC-002**: Operators can re-provision an existing node with a different OS image in under 30 minutes by updating software_image_name variable and triggering power_cycle
- **SC-003**: Module successfully provisions 5 nodes sequentially without exceeding provisioning slot limits and completes all nodes within 150 minutes
- **SC-004**: Module successfully provisions 10 nodes in parallel (up to slot limit) completing all nodes in under 60 minutes total elapsed time
- **SC-005**: 100% of provisioned nodes report correct hostname, IP assignments, and category in Terraform outputs after provisioning completes
- **SC-006**: Module prevents BMC credential exposure in Terraform state, console output, and logs through proper sensitive variable handling
- **SC-007**: Module fails gracefully during plan phase when software image or network names don't exist on BCM headnode, preventing partial provisioning
- **SC-008**: Module handles node provisioning failures without affecting other nodes in parallel provisioning scenarios - 1 failed node out of 10 does not block the other 9
- **SC-009**: Operators can identify provisioning failures through Terraform outputs showing per-node success/failure status within 1 minute of provisioning completion
- **SC-010**: Module documentation enables operators to verify all 10 documented prerequisites in under 10 minutes before first provisioning attempt

### Qualitative Outcomes

- Operators express confidence in unattended bulk provisioning for cluster scaling operations
- Operators report reduced time spent on manual bare metal provisioning tasks
- Operators successfully use module for both initial deployments and ongoing lifecycle management (patching, upgrades)
- Module integrates seamlessly into existing Terraform workflows with existing BCM provider usage in root module

## Scope & Boundaries *(mandatory)*

### In Scope

- Terraform child module for reusable node provisioning automation
- Both new node provisioning (power_on) and existing node re-provisioning (power_cycle)
- Support for any number of nodes via configurable nodes variable
- Sequential and parallel provisioning modes
- Category management with custom configuration (install_mode, BMC settings, disk setup, scripts, kernel parameters)
- IPMI power control via Terraform Actions feature
- Data source lookups for existing software images, categories, and networks
- Node status querying and output reporting
- BMC credential management via sensitive variables
- Module documentation with prerequisite checklist
- Example usage for common provisioning scenarios

### Out of Scope

- BCM headnode installation and initial configuration (prerequisite)
- Software image creation, preparation, or management (images must pre-exist on headnode)
- DHCP/TFTP/PXE server setup (prerequisite)
- Network infrastructure configuration (networks must pre-exist)
- Provisioning role and slot configuration on headnode (prerequisite)
- Validation or enforcement of documented prerequisites
- Orchestration of workload migration before re-provisioning
- Automatic detection of node hardware failures
- Backup and restore of node data before re-provisioning
- Custom software image building or modification
- Certificate Authority setup or management
- Configuration management after OS provisioning completes (Ansible, Kubernetes, etc.)
- Monitoring and alerting for provisioning status
- Integration with external CMDB or inventory systems
- Automatic retry logic for failed power actions
- Cost estimation or resource usage tracking

## Assumptions *(mandatory)*

1. **BCM Headnode Operational**: BCM 10 headnode is fully installed, configured, and operational with all required services (DHCP, TFTP, PXE, DNS, CA) before module is used
2. **Software Images Pre-exist**: All software images referenced by `software_image_name` variable are already imported/prepared on BCM headnode and available via data source lookup
3. **Network Pre-configuration**: All networks referenced in module configuration (management_network, production networks) are already configured in BCM with appropriate DHCP ranges
4. **BMC Connectivity**: All target nodes have functioning BMC interfaces with network connectivity from BCM headnode to BMC IP addresses on OOB network (10.229.10.0/24)
5. **Provisioning Infrastructure Ready**: Provisioning role is active on headnode with localimages configured, provisioning slots are adequate for workload, and provisioning threads are configured per prerequisites
6. **Terraform Version**: Operators are using Terraform 1.14 or later to support Actions feature required for power actions
7. **Provider Availability**: hashi-demo-lab/bcm provider version ~> 0.1 is available and properly configured with credentials for BCM API access
8. **Hardware Compatibility**: All target nodes support PXE boot, have IPMI-compatible BMC interfaces, and are compatible with assigned software images
9. **MAC Address Accuracy**: MAC addresses provided in node configuration are accurate and match physical hardware
10. **No Concurrent Modifications**: Operators do not manually modify BCM device records, categories, or power states outside Terraform during provisioning operations
11. **Network Isolation**: IPMI traffic is properly isolated to OOB management network (10.229.10.0/24) via network configuration
12. **Credential Security**: Operators manage BMC credentials securely (via environment variables, encrypted backends, or secret management systems) and do not commit to version control
13. **Workload Safety**: Operators ensure nodes are drained of critical workloads before triggering re-provisioning power_cycle actions (module does not validate or enforce this)
14. **Provisioning Time**: Standard node provisioning completes within 30 minutes under normal conditions (actual time depends on image size, network speed, hardware performance)
15. **Slot Configuration**: Default BCM provisioning slot limit is 10; operators increase slot limit if parallel provisioning >10 nodes
16. **Existing Integration**: Root module already uses data.bcm_cmdevice_nodes for node discovery, indicating BCM provider is configured and functional
17. **Project Context**: Module is designed for specific project context with control plane nodes (cpu-03, cpu-05, cpu-06) and GPU workers (dgx-05, dgx-06) on production network 10.184.162.0/24
18. **No Cloud Credentials**: This is bare metal infrastructure; no cloud provider credentials are involved or required
19. **Idempotent Operations**: Terraform state accurately reflects BCM state; repeated applies without configuration changes do not trigger unnecessary power actions
20. **Documentation Accessibility**: Operators have access to BCM 10 documentation for troubleshooting provisioning failures and advanced configuration

## Dependencies *(mandatory)*

### External Dependencies

1. **BCM 10 Headnode**: Fully functional BCM 10 installation with management interface, API access, and all provisioning services operational
2. **BCM Provider**: hashi-demo-lab/bcm Terraform provider version ~> 0.1 installed and configured with valid API credentials
3. **Network Infrastructure**: Physical network infrastructure providing connectivity for management network (10.184.162.0/24) and OOB/IPMI network (10.229.10.0/24)
4. **DHCP Service**: DHCP server running on BCM headnode providing IP address assignment during PXE boot process
5. **TFTP Service**: TFTP server running on BCM headnode providing boot files and configuration during PXE process
6. **PXE Boot Infrastructure**: PXE server on headnode configured with boot images and provisioning scripts
7. **Certificate Authority**: BCM CA operational for secure communication during provisioning
8. **Software Images**: Pre-built OS images imported into BCM headnode localimages repository
9. **DNS Service**: DNS resolution operational for hostname registration and lookup during provisioning
10. **BMC Firmware**: IPMI-compatible firmware running on all target node BMC interfaces with power control and console redirection capabilities

### Internal Dependencies

1. **Terraform Version**: Terraform >= 1.14 required for Actions feature support in bcm_cmdevice_power resource
2. **Root Module Configuration**: Existing root module with BCM provider configuration (provider credentials, endpoint)
3. **Node Hardware**: Physical bare metal nodes (DGX and CPU servers) with functional BMC interfaces, network cards supporting PXE boot
4. **Credential Management**: Secure mechanism for providing BMC credentials (environment variables, Terraform variables, secret management)
5. **Provisioning Configuration Files**: BCM configuration files on headnode with correct settings (DeviceResolveAnyMAC=1, MaxNumberOfProvisioningThreads)

### Sequential Dependencies (Within Module)

1. **Data Source Lookups → Device Creation**: Software image and network data sources must resolve before device resources can be created (software_image_id, network_id references)
2. **Device Creation → Power Actions**: bcm_cmdevice_device resources must exist before bcm_cmdevice_power actions can be triggered (requires device ID)
3. **Power Actions → Status Query**: Power actions should complete before data.bcm_cmdevice_nodes queries for final status (though query can run during provisioning for progress monitoring)
4. **Category Creation → Device Assignment**: If creating custom categories, bcm_cmdevice_category resources must exist before devices can reference them via category attribute

### Optional Dependencies

1. **Parallel Provisioning**: When provisioning_mode is "parallel", adequate provisioning slots must be available on headnode (default 10, configurable in /etc/cmd.conf)
2. **Custom Categories**: When using custom categories with initialize/finalize scripts, scripts must be available on headnode at expected paths
3. **Advanced Disk Setup**: When using custom disksetup configurations, headnode must support specified disk layout options
4. **Kernel Modules**: When specifying custom modules in category, kernel modules must exist in software image or be available for dynamic loading

## Risks & Mitigations *(optional)*

### Risk 1: Provisioning Slot Exhaustion

**Risk**: Parallel provisioning of more nodes than available slots causes queuing delays or provisioning failures
**Likelihood**: Medium  
**Impact**: Medium (delays but doesn't break provisioning)  
**Mitigation**: Document provisioning slot limits prominently in README; recommend operators verify slot configuration before large-scale parallel provisioning; module respects BCM slot limits and queues overflow

### Risk 2: BMC Connectivity Failures

**Risk**: IPMI power actions fail due to BMC network connectivity issues (misconfigured OOB network, firewall rules, BMC firmware issues)
**Likelihood**: Medium  
**Impact**: High (prevents provisioning from starting)  
**Mitigation**: Document BMC connectivity as critical prerequisite; recommend operators test IPMI connectivity manually before using module; module surfaces clear error messages indicating BMC connectivity failure

### Risk 3: Incorrect MAC Address Configuration

**Risk**: Operator provides wrong MAC address in node configuration causing PXE boot to fail or wrong node to provision
**Likelihood**: Low  
**Impact**: High (wrong node provisioned or provisioning failure)  
**Mitigation**: Document MAC address verification in README; recommend operators cross-reference MAC addresses from hardware labels or BIOS; module validates MAC address uniqueness

### Risk 4: Accidental Re-provisioning of Production Nodes

**Risk**: Operator triggers power_cycle on production node without draining workloads, causing data loss or service disruption
**Likelihood**: Medium  
**Impact**: Critical (data loss, service outage)  
**Mitigation**: Document workload safety responsibility clearly in README; require explicit power_action variable opt-in (not defaulted); recommend operators use separate state files or workspaces for production vs non-production

### Risk 5: Software Image Mismatch

**Risk**: Operator assigns incompatible software image to node type (e.g., CPU-only image to DGX GPU node)
**Likelihood**: Low  
**Impact**: Medium (node boots but lacks required drivers/software)  
**Mitigation**: Document image compatibility requirements in README; recommend operators maintain clear naming convention for images indicating target hardware; node will boot but may report errors for missing components

### Risk 6: Terraform State Drift

**Risk**: Manual changes to BCM device records outside Terraform cause state drift, leading to unexpected behavior on next apply
**Likelihood**: Medium  
**Impact**: Medium (potential unintended resource recreation)  
**Mitigation**: Document that all BCM modifications should go through Terraform; recommend operators use terraform refresh before applies; module uses lifecycle rules to prevent unnecessary recreation

### Risk 7: Credential Exposure

**Risk**: BMC credentials accidentally committed to version control or exposed in logs/console output
**Likelihood**: Low  
**Impact**: High (security vulnerability)  
**Mitigation**: Mark all credential variables as sensitive; document secure credential management practices in README; recommend using environment variables or encrypted backends

### Risk 8: Provisioning Timeout Without Clear Status

**Risk**: Node provisioning hangs indefinitely without clear indication of failure, leaving operator uncertain whether to intervene
**Likelihood**: Low  
**Impact**: Medium (operational confusion, wasted time)  
**Mitigation**: Document expected provisioning timeline (30 minutes) in README; recommend operators monitor BCM logs for detailed status; module queries and outputs node state for status verification

### Risk 9: Insufficient Headnode Resources

**Risk**: Parallel provisioning of many nodes overwhelms headnode CPU/memory/network, causing provisioning failures or slowdowns
**Likelihood**: Low  
**Impact**: Medium (provisioning failures or delays)  
**Mitigation**: Document headnode resource requirements in prerequisites; recommend operators monitor headnode during provisioning; BCM provisioning slot limits inherently prevent excessive resource usage

### Risk 10: Power Action Idempotency Issues

**Risk**: Repeated terraform applies trigger repeated power cycles on nodes unintentionally
**Likelihood**: Low  
**Impact**: Medium (service disruption, unnecessary wear on hardware)  
**Mitigation**: Use Terraform Actions feature which is designed for explicit execution; require power_action variable opt-in; document power action behavior clearly in README

## Open Questions *(optional)*

*No open questions at this time. All aspects of the feature are sufficiently specified for planning phase.*

## Notes *(optional)*

- This module is specifically designed for the documented project context (BCM 10, production network 10.184.162.0/24, OOB network 10.229.10.0/24, specific control plane and GPU worker nodes) but should be generalizable to other BCM environments
- The use of Terraform 1.14+ Actions feature for power management is a critical architectural decision - operators must ensure they have the required Terraform version
- While the module automates provisioning, operators remain responsible for lifecycle management decisions (when to re-provision, workload migration, capacity planning)
- The module intentionally does not validate prerequisites to avoid complexity - prerequisite verification is operator responsibility documented in README
- Future enhancements could include: automatic retry logic for failed power actions, integration with monitoring/alerting systems, cost/time estimation for provisioning jobs, automatic workload migration before re-provisioning
