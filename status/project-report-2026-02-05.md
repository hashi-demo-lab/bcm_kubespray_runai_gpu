Project Report: Automated Kubernetes + Run:AI GPU Platform on NVIDIA DGX Bare Metal

Repository: https://github.com/hashi-demo-lab/bcm_kubespray_runai_gpu
Date: February 5, 2026
Authors: Randy Keener, Simon Lynch
Target Environment: NVIDIA DGX bare metal (5 nodes) managed by Base Command Manager (BCM)

---
Executive Summary

This project delivers a fully automated, end-to-end deployment pipeline for a production Kubernetes cluster with Run:AI v2.21 self-hosted GPU workload scheduling on NVIDIA DGX bare metal infrastructure. Starting from raw BCM-managed hardware, a single Terraform workflow discovers physical nodes, deploys Kubernetes v1.31.9 via Kubespray, and installs a complete platform stack of 10+ components including GPU Operator, Prometheus monitoring, Knative inference serving, and the Run:AI control plane with Keycloak authentication.

The project was completed in approximately seven weeks (December 18, 2025 to February 5, 2026) with 109 commits across 86 files. The original design intent was to use the BCM Terraform provider's native Kubernetes deployment API (bcm_cmkube_cluster) to provision the cluster directly. However, the BCM API lacked the operational granularity required for production requirements -- specifically version pinning, CNI selection, and component customization. The team pivoted to a Kubespray-based approach that retains BCM for node discovery while using Ansible for Kubernetes deployment, resulting in a more flexible and controllable architecture.

---
What This Project Does

This platform solves the problem of deploying a complete, production-grade AI/ML training and inference environment on NVIDIA DGX bare metal, entirely from code. Before this project, deploying such an environment required extensive manual configuration across multiple systems, weeks of engineering time, and deep knowledge of several distinct technology domains.

The automated pipeline covers:

- Physical node discovery and inventory generation from the BCM management API
- SSH user provisioning with key-based authentication across all cluster nodes
- Kubernetes v1.31.9 deployment with Calico CNI, 3-node HA control plane, and 2 GPU worker nodes
- NVIDIA GPU Operator v25.3.3 installation with driver validation and containerd configuration
- Complete Run:AI v2.21 self-hosted backend including Keycloak OIDC authentication, PostgreSQL, Redis, Thanos, and Grafana
- Run:AI cluster agent deployment for GPU scheduling with automatic cluster registration via API
- Supporting infrastructure: Prometheus monitoring, Knative serverless inference, LeaderWorkerSet distributed training, and NGINX ingress

The target cluster consists of five physical nodes:

- 3 control plane nodes (cpu-03, cpu-05, cpu-06) running Kubernetes control plane and etcd
- 2 GPU worker nodes (dgx-05, dgx-06) running NVIDIA DGX hardware for AI workloads
- Production network: 10.184.162.0/24
- Pod CIDR: 172.29.0.0/16 (Calico)
- Service CIDR: 10.150.0.0/16

---
How It Works: Three-Stage Architecture

The deployment executes in three sequential stages, each building on the output of the previous stage.

Stage 1: Node Discovery (BCM API)

Terraform queries the BCM management API using the bcm_cmdevice_nodes data source to enumerate all physical nodes in the cluster. Nodes are filtered by hostname to identify control plane nodes (cpu-03/05/06) and GPU workers (dgx-05/06). The BCM API returns node metadata including UUIDs, MAC addresses, hardware type, and network interfaces. Critically, the project extracts production network IP addresses (10.184.162.x) rather than BCM management network IPs (10.229.10.x), as the management network is reserved for out-of-band hardware administration.

Stage 2: Kubernetes Deployment (Kubespray via Ansible)

Terraform orchestrates a multi-step Ansible workflow to deploy Kubernetes:

1. A 4096-bit RSA SSH key pair is auto-generated and distributed
2. An ansiblebcm service account (UID 60000) is created on all nodes with passwordless sudo via an Ansible playbook
3. A Kubespray-compatible YAML inventory is generated from BCM node data
4. Kubespray v2.27.1 is cloned, a Python virtual environment is created, and the cluster.yml playbook executes to deploy Kubernetes v1.31.9
5. The kubeconfig is extracted from the control plane and made available for Stage 3

Stage 3: Platform Services (Helm)

A child Terraform module (helm_platform/) deploys 10+ Helm charts in strict dependency order:

1. local-path-provisioner -- default StorageClass for persistent volumes
2. NGINX Ingress Controller -- NodePort on 30080/30443
3. NVIDIA GPU Operator v25.3.3 -- drivers, device plugin, DCGM exporter
4. kube-prometheus-stack v77.6.2 -- Prometheus, Alertmanager, Grafana
5. Prometheus Adapter + Metrics Server -- custom and resource metrics
6. LeaderWorkerSet Operator v0.7.0 -- distributed training jobs
7. Knative Operator v1.16.0 -- serverless inference
8. Run:AI Backend v2.21 -- Keycloak, PostgreSQL, Redis, Thanos, control plane
9. Run:AI Cluster v2.21 -- scheduler, agent, and GPU resource management

Every component can be individually enabled or disabled via toggle variables, allowing incremental deployment and troubleshooting.

---
The BCM API Approach: What We Tried and Why We Pivoted

The project's original design called for using the BCM Terraform provider's bcm_cmkube_cluster resource to deploy Kubernetes directly through the BCM API. This approach would have been the most elegant solution -- a single Terraform resource call to the BCM management plane that handles the entire Kubernetes lifecycle natively. The BCM system includes a comprehensive cm-kubernetes-setup.conf configuration (1,300+ lines) covering Kubernetes version, operators, CNI, networking, and node-specific packages.

However, during implementation we identified critical functional gaps in the BCM API that precluded production use:

- Limited Kubernetes version control: The API only supported BCM-curated Kubernetes versions, with no ability to pin a specific patch release. Run:AI v2.21 requires K8s 1.30-1.32 with specific patch-level compatibility.
- No CNI selection: The API defaulted to BCM's CNI configuration with no option to choose Calico, Flannel, or Cilium with custom pod/service CIDRs.
- Opaque component management: Platform components (GPU Operator, monitoring, ingress) were managed as BCM "operators" with fixed versions and limited configuration. Run:AI required specific compatible versions of GPU Operator (v24.9-25.3), Knative (v1.11-1.16), and other components that the BCM operator catalog did not precisely match.
- No Ansible integration: The BCM-native approach is a black box with no ability to customize Kubespray playbooks, node preparation scripts, or post-deployment configuration.
- Limited debugging: Failures surfaced as opaque API error responses rather than the detailed Ansible output available with Kubespray.
- Provider maturity: The BCM Terraform provider (v0.1) exhibited bugs including phantom diffs on authorized_ssh_keys changes, requiring lifecycle ignore_changes workarounds.

The team pivoted to retain BCM for what it does well -- node discovery and hardware inventory -- while using Kubespray v2.27.1 for Kubernetes deployment. This gave us full control over every aspect of the cluster configuration and enabled precise version alignment with Run:AI requirements.

The bcm_cmkube_cluster module has been preserved in the repository as a reference implementation, documenting BCM's native capabilities for future comparison.

Recommendation: We strongly recommend continued development of the BCM Kubernetes API to support configurable Kubernetes versions, CNI selection, custom pod/service CIDRs, and granular component version pinning. If these capabilities are added, a future iteration of this project could eliminate the Kubespray dependency entirely, reducing deployment complexity and providing a tighter integration between BCM hardware management and Kubernetes lifecycle operations. The BCM Terraform provider should also be hardened to production quality, addressing the phantom diff bugs and adding user management resources.

---
Key Achievements

- Delivered a repeatable, code-driven deployment that takes NVIDIA DGX bare metal from raw hardware to a fully operational AI platform with GPU scheduling in a single Terraform workflow
- Automated user provisioning across BCM-managed nodes, overcoming the lack of user management APIs by implementing a multi-stage Ansible playbook with intelligent existence detection and dual authentication support (password and key-based)
- Deployed Run:AI v2.21 self-hosted with full Keycloak OIDC authentication, self-signed TLS with custom CA propagation, and automated cluster registration via the Run:AI API, eliminating manual UI steps
- Built GPU node preparation automation that handles containerd relocation from space-constrained /var partitions to larger data partitions, NVIDIA driver validation, and Docker Hub registry mirroring to avoid pull rate limits
- Created a comprehensive operational toolkit including preinstall diagnostics, kubeconfig setup helpers, NFS-safe Helm configuration, and documented troubleshooting procedures
- Achieved full version alignment with Run:AI v2.21 requirements across Kubernetes (v1.31.9), GPU Operator (v25.3.3), Knative (v1.16.0), and all supporting components
- Maintained infrastructure-as-code principles throughout -- every configuration decision is captured in Terraform, reproducible, and version-controlled

---
Issues Encountered and How They Were Resolved

Issue 1: BCM Management Network vs. Production Network Confusion

The BCM API returns multiple network interfaces per node, including both the management network (10.229.10.x) used for out-of-band hardware administration and the production network (10.184.162.x) used for application traffic. Early iterations of the node discovery logic selected the wrong network, causing Kubespray to attempt deployment over the management network where Kubernetes traffic is not routed.

Resolution: Implemented explicit production network filtering in Terraform locals with a hardcoded CIDR match (10.184.162.0/24) and a var.node_production_ips override map for cases where automatic detection fails. Added clear documentation warning against using the management network for deployment. This required refactoring the entire network query structure across main.tf and locals.tf .

Issue 2: SSH Authentication on BCM-Managed Nodes

BCM-provisioned nodes use the ibm admin account with password-based SSH authentication and may reset SSH host keys on reboot. The project needed to bootstrap a dedicated ansiblebcm service account with key-based authentication starting from password-only access, while handling legacy SSH algorithms (ssh-rsa, ssh-dss) that modern SSH clients reject by default.

Resolution: Built a multi-layer authentication system. The initial bootstrap uses sshpass with the ibm admin password to create the ansiblebcm account (UID 60000) via an Ansible playbook. All subsequent operations use the auto-generated 4096-bit RSA key pair. SSH connection commands include explicit algorithm overrides (-o HostKeyAlgorithms=+ssh-rsa,ssh-dss) for backward compatibility. A precondition check prevents deployment if the user exists on some but not all nodes, catching partial-state failures early. This required 12 iterative commits to stabilize (commits 556f9c3 through 048c6e5).

Issue 3: Ansible Vault Permission Conflicts

When Terraform invokes Ansible for user creation and Kubespray deployment, system-level Ansible configuration files can inject unexpected ANSIBLE_VAULT_PASSWORD_FILE settings, causing vault permission errors entirely unrelated to the deployment task.

Resolution: Created a minimal project-specific ansible.cfg that disables vault password, retry files, and host key checking. The Terraform provisioner explicitly unsets ANSIBLE_VAULT_PASSWORD_FILE and ANSIBLE_VAULT_PASSWORD environment variables and sets ANSIBLE_CONFIG to point at the project's ansible.cfg. This required five iterative fias each workaround revealed additional vault configuration entry points.

Issue 4: Run:AI Helm Chart Custom CA Configuration

Run:AI v2.21 self-hosted uses self-signed TLS certificates, requiring custom CA trust to be propagated to every component. However, the Run:AI Helm charts have three different and underdocumented mechanisms for CA configuration: the control-plane chart uses customCA with volumes/volumeMounts/env, the pre-install job uses customCA.secretName/secretKey, and keycloakx uses a completely separate extraEnv structure. Setting one mechanism broke another due to Helm value merging conflicts.

Resolution: Through systematic testing, we identified the correct value structure for each component and consolidated all CA configuration into a single Helm values block to avoid set/values conflicts. The keycloakx configuration was separated from the main Helm values to prevent duplicate block overwrites. This was the single most iterative issue in the project, requiring 10 consecutive fix commits (commits c268fcc through 226e8a7) to resolve all CA propagation paths.

Issue 5: Keycloak OIDC External Endpoint Configuration

Run:AI's Keycloak instance must advertise an externally-reachable OIDC issuer URL that includes the correct hostname and NodePort. The global.domain Helm value controls internal routing, while KC_HOSTNAME and keycloakExternalEndpoint control external token validation. Setting global.domain to include the port number broke internal service discovery, but omitting it broke external OIDC token validation.

Resolution: Separated the internal and external configuration: global.domain uses the hostname only (bcm-head-01.eth.cluster), while KC_HOSTNAME is set via keycloakx.extraEnvVars to include the NodePort (bcm-head-01.eth.cluster:30443), and keycloakExternalEndpoint is configured with the full port specification. This required understanding undocumented interactions between three separate Helm value paths .

Issue 6: DNS Resolution for Run:AI Domain Inside the Cluster

Pods inside the Kubernetes cluster could not resolve the Run:AI domain (bcm-head-01.eth.cluster) because it was not registered in internal DNS. Run:AI backend services and the cluster agent both need to reach the control plane by its external hostname.

Resolution: Implemented a nodelocaldns configuration fix that patches the CoreDNS configmap to add a hosts plugin entry resolving the Run:AI domain to the control plane IP. This is applied as a null_resource that executes kubectl commands after the Run:AI backend is deployed (commit 0d68e98).

Issue 7: DGX Containerd Disk Space Exhaustion

NVIDIA DGX nodes are provisioned by BCM with approximately 6GB available on the /var partition. The GPU Operator's driver container images require approximately 3GB, leaving insufficient space for normal containerd operations and causing image pull failures.

Resolution: Created a relocate-containerd.sh script that safely stops the containerd service, migrates storage from /var/lib/containerd to a larger partition (/local/containerd, typically >100GB on DGX nodes), creates a symlink, and restarts the service. This is a prerequisite step validated by the check-gpu-operator-prereqs.sh diagnostic tool before GPU Operator installation proceeds.

Issue 8: Run:AI Cluster Registration Automation

Run:AI's documented workflow requires manually logging into the UI, navigating to cluster management, creating a new cluster, and copying the generated client secret and cluster UID back into the Terraform configuration. This manual step breaks the fully automated pipeline.

Resolution: Implemented API-driven cluster creation using a null_resource that authenticates against the Run:AI backend Keycloak instance, obtains an access token, and calls the Run:AI cluster creation API endpoint. The returned credentials are written to a temporary file and read back by a data source for use in the Run:AI cluster Helm chart deployment. Initial attempts using data.external failed because it does not support environment variables; the null_resource approach resolved this .

Issue 9: Terraform Sensitive Value Propagation

Kubernetes provider credentials (CA certificate, client certificate, client key) are output from the root module as sensitive values. The helm_platform child module needed to base64-decode these values, but Terraform's base64decode() function does not accept sensitive inputs, and the nonsensitive() function created security warnings.

Resolution: Moved base64 decoding to the provider level configuration rather than in locals, and used trimspace() to handle whitespace in base64-encoded credentials that caused decoding failures. The kubeconfig was ultimately refactored to use file-based authentication (writing a kubeconfig file to disk) rather than embedding credentials in the provider block, which eliminated the sensitivity propagation issue entirely (commits 1d49ee8 through ed2db7f).

Issue 10: Helm NFS File Locking on Control Plane Nodes

BCM-provisioned control plane nodes mount home directories via NFS. Helm requires file locking for its cache and configuration directories, which NFS does not support, causing "no locks available" errors on every Helm operation.

Resolution: Created setup-helm-nfs.sh that redirects Helm's cache, config, and data directories to /tmp/helm-* using HELM_CACHE_HOME, HELM_CONFIG_HOME, and HELM_DATA_HOME environment variables. This script must be sourced before any Helm operations on the control plane nodes.

---
Technology Stack and Versions

- Terraform: Infrastructure orchestration and state management
- BCM Terraform Provider: v0.1.3 (hashi-demo-lab/bcm) -- node discovery
- Ansible Terraform Provider: v1.3 -- Kubespray execution
- Kubespray: v2.27.1 -- Kubernetes deployment
- Kubernetes: v1.31.9 with Calico CNI
- Run:AI: v2.21 self-hosted (backend + cluster)
- GPU Operator: v25.3.3 (NVIDIA)
- Knative: v1.16.0
- kube-prometheus-stack: v77.6.2
- NGINX Ingress Controller: v4.9.0
- LeaderWorkerSet Operator: v0.7.0
- Metrics Server: v3.13.0
- Python: 3.10+ (Kubespray requirement)

---
Recommendations

1. Invest in BCM API maturity for Terraform integration. The current BCM Kubernetes API should be extended to support configurable Kubernetes versions, CNI plugin selection, custom network CIDRs, and granular component version pinning. This would allow future deployments to use the bcm_cmkube_cluster resource directly, eliminating the Kubespray dependency and reducing the deployment pipeline from three stages to two. The BCM Terraform provider (v0.1) should also be hardened to production quality, addressing phantom diff bugs and adding user management resources.

2. Establish a CI/CD pipeline with terraform validate and plan. The current development process relies entirely on manual terraform plan/apply cycles. Automated validation would catch syntax errors, provider incompatibilities, and regression issues before they reach the deployment stage.

3. Document the known-good Run:AI Helm configuration as a reusable reference. The custom CA, Keycloak, and DNS configuration required extensive iterative discovery. Capturing the final working values in a consumable format will accelerate future deployments and prevent regression.

4. Create a tagged baseline release (v1.0.0). The project has reached functional completeness. A versioned release establishes a rollback point and formal change tracking for production operations.

5. Consider contributing the BCM Terraform provider improvements upstream. The node discovery pattern, network filtering logic, and workarounds for provider bugs developed in this project would benefit other BCM customers deploying Kubernetes on DGX infrastructure.

6. Evaluate upgrading the containerd relocation from a manual script to a Terraform-managed resource. This is currently the one remaining manual prerequisite step that breaks the fully automated pipeline.

---
Note

- The deployment is idempotent -- running terraform apply multiple times will not create duplicate resources or break existing configuration. Components that are already deployed will be skipped.

- All component versions are pinned and aligned with Run:AI v2.21 system requirements. Upgrading any individual component should be validated against Run:AI's compatibility matrix before proceeding.

- The Run:AI backend uses NodePort ingress (ports 30080/30443) rather than a LoadBalancer, because bare metal environments typically do not have a cloud load balancer. Access the Run:AI UI at https://<control-plane-hostname>:30443.

- GPU nodes must have containerd relocated to a partition with at least 10GB free space before the GPU Operator will function correctly. The scripts/relocate-containerd.sh tool handles this safely.

- Self-signed TLS certificates are used throughout. Browser access to the Run:AI UI will require accepting the certificate warning. If integrating with external systems, the CA certificate must be explicitly trusted.

- The BCM management network (10.229.10.x) must never be used for Kubernetes traffic. All deployment, pod-to-pod, and service communication uses the production network (10.184.162.x).

- The project includes toggle variables for every component, allowing selective deployment. For example, set enable_runai = false to deploy only the Kubernetes cluster and GPU Operator without the Run:AI platform.

- The bcm_cmkube_cluster/ directory in the repository is a reference implementation only and is not used in the production deployment flow. It documents BCM's native Kubernetes API capabilities for future evaluation.

---
Report generated February 5, 2026.
