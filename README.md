# vSphere Kubernetes Cluster Deployment with Kubespray

Terraform configuration for deploying a 3-node Kubernetes cluster on VMware vSphere infrastructure using Kubespray.

## Overview

This Terraform project automates the provisioning of three Ubuntu virtual machines on vSphere and deploys a production-ready Kubernetes cluster using Kubespray Ansible playbooks.

**Cluster Architecture:**
- 1x Control Plane Node (k8s-master-01): Runs Kubernetes control plane components and etcd
- 2x Worker Nodes (k8s-worker-01, k8s-worker-02): Run containerized workloads

**Key Features:**
- Automated VM provisioning with static IP configuration
- Kubespray-based Kubernetes deployment
- CNI plugin support (Calico, Flannel, Cilium)
- HCP Terraform remote state management
- Security-first design with SSH key-based authentication

## Prerequisites

### Infrastructure Requirements

- VMware vSphere environment (vCenter/ESXi)
- Ubuntu LTS VM template (tested with 22.04)
- Network with static IP allocation
- Minimum 6 vCPUs and 12GB RAM available (2 CPU / 4GB per node)

### Software Requirements

- Terraform >= 1.5.0
- HCP Terraform account and organization access
- SSH key pair for VM access
- Kubespray repository cloned locally

### vSphere Permissions

The following vSphere permissions are required:
- Virtual Machine > Configuration > All
- Virtual Machine > Interaction > All
- Datastore > Allocate space
- Network > Assign network
- Resource > Assign virtual machine to resource pool

## Quick Start

### 1. Configure Variables

Copy the example tfvars file and update with your environment details:

```bash
cp sandbox.auto.tfvars.example sandbox.auto.tfvars
```

Edit `sandbox.auto.tfvars` and configure your vSphere infrastructure, network, and Kubernetes settings.

### 2. Configure HCP Terraform

Set your HCP Terraform organization token:

```bash
terraform login
```

Update `override.tf` to point to your workspace.

### 3. Configure Workspace Variables

In your HCP Terraform workspace, configure sensitive variables for SSH keys and vSphere credentials.

### 4. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

Total deployment time: Approximately 16-25 minutes

### 5. Access the Cluster

Retrieve kubectl configuration from outputs and configure local kubectl access.

## Architecture

This project uses the approved private module `tfo-apj-demos/single-virtual-machine/vsphere` v1.4.2 from the HCP Terraform private registry, adhering to the module-first architecture principle.

**Deployment Flow:**
1. Terraform provisions 3 VMs via private module
2. null_resource waits for SSH connectivity on all VMs
3. local_file generates Kubespray inventory from VM outputs
4. ansible_playbook executes Kubespray cluster deployment
5. Kubernetes cluster becomes operational

## Network Requirements

The following ports must be accessible between cluster nodes:

**Control Plane:**
- 6443: Kubernetes API server
- 2379-2380: etcd server client API
- 10250: Kubelet API
- 10259: kube-scheduler
- 10257: kube-controller-manager

**Worker Nodes:**
- 10250: Kubelet API
- 30000-32767: NodePort Services

**All Nodes:**
- 22: SSH (for Ansible)
- CNI-specific ports (e.g., Calico: 179 BGP)

## Edge Cases and Error Handling

**Insufficient vSphere Resources (FR-008):**
- Module will fail with clear error message about resource constraints
- Resolution: Free up resources or adjust VM size parameters

**Network Connectivity Issues:**
- SSH wait timeout (5 minutes) will halt deployment
- Resolution: Verify firewall rules and network configuration

**Kubespray Deployment Failures:**
- Ansible playbook errors captured in Terraform output
- Resolution: Check Ansible logs, verify OS compatibility, ensure all nodes are accessible

**State Inconsistency:**
- If deployment fails mid-execution, run `terraform refresh` to sync state
- Consider `terraform destroy` and retry for clean slate

## Security Considerations

**SEC-001**: No hardcoded credentials - all sensitive data via HCP Terraform workspace variables
**SEC-002**: SSH key-based authentication - keys stored as sensitive variables
**SEC-007**: Security profile parameter enforced per organizational standards
**SEC-008**: Terraform state encrypted at rest and in transit via HCP Terraform
**SEC-009**: SSH access should be restricted in production (consider bastion host pattern)

## Troubleshooting

**VM Provisioning Failures:**
- Check vSphere capacity and permissions
- Verify Ubuntu template exists and is accessible
- Review module logs in Terraform output

**SSH Connectivity Timeouts:**
- Verify firewall rules allow SSH traffic
- Ensure SSH keys are correctly configured in workspace variables
- Check VM network configuration and IP allocation

**Kubespray Execution Errors:**
- Verify Kubespray playbook path is correct
- Check Ubuntu VM meets minimum requirements (2 CPU, 4GB RAM)
- Review Ansible logs for specific error messages
- Ensure Python is installed on all VMs

## Documentation

- Feature Specification: `/workspace/specs/001-vsphere-k8s-kubespray/spec.md`
- Implementation Plan: `/workspace/specs/001-vsphere-k8s-kubespray/plan.md`
- Data Model: `/workspace/specs/001-vsphere-k8s-kubespray/data-model.md`
- Task List: `/workspace/specs/001-vsphere-k8s-kubespray/tasks.md`

## Terraform Documentation

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_ansible"></a> [ansible](#requirement\_ansible) | ~> 1.3.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | ~> 2.4.0 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.2.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_ansible"></a> [ansible](#provider\_ansible) | 1.3.0 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.4.1 |
| <a name="provider_null"></a> [null](#provider\_null) | 3.2.4 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_k8s_control_plane_01"></a> [k8s\_control\_plane\_01](#module\_k8s\_control\_plane\_01) | app.terraform.io/tfo-apj-demos/single-virtual-machine/vsphere | 1.4.2 |
| <a name="module_k8s_worker_01"></a> [k8s\_worker\_01](#module\_k8s\_worker\_01) | app.terraform.io/tfo-apj-demos/single-virtual-machine/vsphere | 1.4.2 |
| <a name="module_k8s_worker_02"></a> [k8s\_worker\_02](#module\_k8s\_worker\_02) | app.terraform.io/tfo-apj-demos/single-virtual-machine/vsphere | 1.4.2 |

## Resources

| Name | Type |
|------|------|
| [ansible_playbook.kubespray_cluster](https://registry.terraform.io/providers/ansible/ansible/latest/docs/resources/playbook) | resource |
| [local_file.kubespray_inventory](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [null_resource.wait_for_vms](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_backup_policy"></a> [backup\_policy](#input\_backup\_policy) | Backup policy for VM data protection. Maps to module 'backup\_policy' input. | `string` | `"daily"` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Kubernetes cluster name identifier (FR-007) | `string` | `"vsphere-k8s-cluster"` | no |
| <a name="input_cni_plugin"></a> [cni\_plugin](#input\_cni\_plugin) | Container Network Interface plugin for pod networking (per FR-010) | `string` | `"calico"` | no |
| <a name="input_control_plane_vm_size"></a> [control\_plane\_vm\_size](#input\_control\_plane\_vm\_size) | VM size tier for control plane node (must meet minimum 2 CPU, 4GB RAM per FR-005). Maps to module 'size' input. | `string` | `"medium"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Deployment environment classification (dev, staging, prod) (FR-002) | `string` | n/a | yes |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Target Kubernetes version for deployment (determined by Kubespray compatibility) (FR-009) | `string` | `"v1.28.5"` | no |
| <a name="input_kubespray_playbook_path"></a> [kubespray\_playbook\_path](#input\_kubespray\_playbook\_path) | Path to Kubespray cluster.yml playbook file (FR-011) | `string` | `"./kubespray/cluster.yml"` | no |
| <a name="input_kubespray_version"></a> [kubespray\_version](#input\_kubespray\_version) | Kubespray release version or Git tag (FR-011) | `string` | `"v2.24.0"` | no |
| <a name="input_security_profile"></a> [security\_profile](#input\_security\_profile) | Security profile classification for VM hardening (per SEC-007). Maps to module 'security\_profile' input. | `string` | `"web-server"` | no |
| <a name="input_service_tier"></a> [service\_tier](#input\_service\_tier) | Service tier classification for resource allocation. Maps to module 'tier' input. | `string` | `"gold"` | no |
| <a name="input_ssh_private_key"></a> [ssh\_private\_key](#input\_ssh\_private\_key) | SSH private key content for VM authentication (per SEC-002, stored in HCP Terraform) (FR-013) | `string` | n/a | yes |
| <a name="input_ssh_private_key_path"></a> [ssh\_private\_key\_path](#input\_ssh\_private\_key\_path) | Path to SSH private key file for Ansible playbook execution | `string` | `"~/.ssh/id_rsa"` | no |
| <a name="input_ssh_user"></a> [ssh\_user](#input\_ssh\_user) | SSH username for VM access and Ansible connectivity (FR-013) | `string` | `"ubuntu"` | no |
| <a name="input_storage_profile"></a> [storage\_profile](#input\_storage\_profile) | Storage performance profile for VM disks (FR-006). Maps to module 'storage\_profile' input. | `string` | `"standard"` | no |
| <a name="input_vm_domain"></a> [vm\_domain](#input\_vm\_domain) | DNS domain for VMs. Maps to module 'ad\_domain' input. | `string` | `"local"` | no |
| <a name="input_vsphere_folder"></a> [vsphere\_folder](#input\_vsphere\_folder) | vSphere folder path for VM organization (FR-001). Maps to module 'folder\_path' input. | `string` | `"Demo Workloads"` | no |
| <a name="input_vsphere_site"></a> [vsphere\_site](#input\_vsphere\_site) | vSphere datacenter/site identifier for VM placement (FR-001). Maps to module 'site' input. | `string` | n/a | yes |
| <a name="input_worker_vm_size"></a> [worker\_vm\_size](#input\_worker\_vm\_size) | VM size tier for worker nodes (must meet minimum 2 CPU, 4GB RAM per FR-005). Maps to module 'size' input. | `string` | `"medium"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_all_node_ips"></a> [all\_node\_ips](#output\_all\_node\_ips) | All Kubernetes node IP addresses for monitoring integration |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Kubernetes cluster name for kubectl configuration |
| <a name="output_cni_plugin"></a> [cni\_plugin](#output\_cni\_plugin) | Deployed CNI plugin for pod networking |
| <a name="output_control_plane_hostname"></a> [control\_plane\_hostname](#output\_control\_plane\_hostname) | Hostname of Kubernetes control plane node |
| <a name="output_control_plane_ip"></a> [control\_plane\_ip](#output\_control\_plane\_ip) | IP address of Kubernetes control plane node for API access |
| <a name="output_control_plane_vm_id"></a> [control\_plane\_vm\_id](#output\_control\_plane\_vm\_id) | vSphere VM ID of control plane node |
| <a name="output_inventory_file_path"></a> [inventory\_file\_path](#output\_inventory\_file\_path) | Path to generated inventory.yml file |
| <a name="output_kubernetes_api_endpoint"></a> [kubernetes\_api\_endpoint](#output\_kubernetes\_api\_endpoint) | Kubernetes API server endpoint (https://<control\_plane\_ip>:6443) |
| <a name="output_kubernetes_version"></a> [kubernetes\_version](#output\_kubernetes\_version) | Deployed Kubernetes version |
| <a name="output_kubespray_inventory"></a> [kubespray\_inventory](#output\_kubespray\_inventory) | Generated Kubespray inventory in YAML format |
| <a name="output_ssh_connection_strings"></a> [ssh\_connection\_strings](#output\_ssh\_connection\_strings) | SSH connection commands for each node |
| <a name="output_ssh_user"></a> [ssh\_user](#output\_ssh\_user) | SSH username for VM access |
| <a name="output_worker_hostnames"></a> [worker\_hostnames](#output\_worker\_hostnames) | Hostnames of Kubernetes worker nodes |
| <a name="output_worker_ips"></a> [worker\_ips](#output\_worker\_ips) | IP addresses of Kubernetes worker nodes |
| <a name="output_worker_vm_ids"></a> [worker\_vm\_ids](#output\_worker\_vm\_ids) | vSphere VM IDs of worker nodes |
<!-- END_TF_DOCS -->
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
