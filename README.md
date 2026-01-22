# BCM Kubernetes Cluster Deployment with Kubespray and Run:AI GPU Support

Terraform configuration for deploying a production-ready Kubernetes cluster on NVIDIA DGX BasePOD infrastructure using BCM (Base Command Manager) for node discovery and Kubespray for cluster deployment.

## Overview

This Terraform project automates the deployment of a Kubernetes cluster on BCM-managed bare metal nodes (such as NVIDIA DGX systems) using Kubespray Ansible playbooks, with support for GPU workloads via Run:AI.

**Cluster Architecture:**

- Control Plane Nodes: Run Kubernetes control plane components and etcd
- Worker Nodes: Run containerized workloads (including GPU workloads)
- etcd Nodes: Defaults to control plane nodes if not specified separately

**Key Features:**

- BCM-based node discovery and inventory generation
- Automated SSH key generation and user provisioning
- Kubespray-based Kubernetes deployment
- CNI plugin support (Calico, Flannel, Cilium)
- GPU operator and Run:AI platform integration
- HCP Terraform remote state management
- Security-first design with auto-generated SSH key authentication

## Prerequisites

### Infrastructure Requirements

- NVIDIA DGX BasePOD or BCM-managed bare metal infrastructure
- BCM (Base Command Manager) with API access
- Network connectivity between nodes and Terraform execution environment
- Minimum 2 CPU / 4GB RAM per node (Kubernetes requirements)

### Software Requirements

- Terraform >= 1.5.0
- HCP Terraform account and organization access
- BCM API credentials
- Python 3.9+ (for Kubespray)

### BCM Permissions

The BCM user account requires:

- Read access to node inventory (`bcm_cmdevice_nodes` data source)
- User management permissions (`bcm_cmuser_user` resource)

## Quick Start

### 1. Configure Variables

Copy the example tfvars file and update with your environment details:

```bash
cp sandbox.auto.tfvars.example sandbox.auto.tfvars
```

Edit `sandbox.auto.tfvars` and configure:

- BCM endpoint and credentials
- Control plane and worker node hostnames
- Kubernetes cluster settings

### 2. Configure HCP Terraform

Set your HCP Terraform organization token:

```bash
terraform login
```

Create `override.tf` with your HCP Terraform backend configuration.

### 3. Configure Workspace Variables

In your HCP Terraform workspace, configure sensitive variables:

- `bcm_username` - BCM API username
- `bcm_password` - BCM API password
- `node_password` - Password for the Ansible service account (optional)

### 4. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

### 5. Access the Cluster

After deployment, retrieve the kubeconfig:

```bash
terraform output -raw kubeconfig_ca_certificate | base64 -d > ca.crt
terraform output kubernetes_api_endpoint
```

## Architecture

**Deployment Flow:**

1. BCM provider discovers available bare metal nodes
2. Terraform filters nodes based on configured hostnames
3. SSH key pair is auto-generated for secure access
4. BCM user resource creates service account with SSH keys on nodes
5. Kubespray inventory is dynamically generated from node data
6. Kubespray Ansible playbooks deploy the Kubernetes cluster
7. (Optional) Helm platform module deploys GPU operator, ingress, and Run:AI

## Configuration

### Node Selection

Specify BCM node hostnames for each Kubernetes role:

```hcl
control_plane_nodes = ["dgx-01", "dgx-02", "dgx-03"]
worker_nodes        = ["dgx-04", "dgx-05", "dgx-06", "dgx-07", "dgx-08"]
etcd_nodes          = []  # Defaults to control_plane_nodes
```

### SSH Key Management

SSH keys are automatically generated using the `tls_private_key` resource:

- A 4096-bit RSA key pair is created
- The public key is added to the BCM user's `authorized_ssh_keys`
- The private key is saved locally for Ansible access
- Additional SSH keys can be provided via `node_user_ssh_public_keys`

### User Configuration

The BCM user resource creates a service account for Ansible:

```hcl
node_username       = "ansible"
node_user_full_name = "Ansible Service Account"
node_user_shell     = "/bin/bash"
```

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

## Project Structure

```
├── main.tf              # BCM node discovery and filtering
├── providers.tf         # BCM and Ansible provider configuration
├── terraform.tf         # Provider version constraints
├── variables.tf         # Input variable declarations
├── outputs.tf           # Output value declarations
├── locals.tf            # Computed values and inventory generation
├── user.tf              # BCM user management with SSH keys
├── ssh_key.tf           # SSH key pair generation
├── ansible.tf           # Kubespray deployment automation
├── inventory.tf         # Kubespray inventory file generation
├── kubeconfig.tf        # Kubeconfig extraction post-deployment
└── helm_platform/       # GPU operator, ingress, Run:AI Helm charts
```

## Security Considerations

- **Auto-generated SSH Keys**: SSH key pairs are generated by Terraform, eliminating the need for pre-existing keys
- **No Hardcoded Credentials**: All sensitive data stored in HCP Terraform workspace variables
- **SSH Key-based Authentication**: Password authentication is supplementary; SSH keys are primary
- **State Encryption**: Terraform state encrypted at rest and in transit via HCP Terraform
- **Sensitive Outputs**: Certificate and key outputs marked as sensitive

## Troubleshooting

**BCM Connection Failures:**

- Verify BCM endpoint URL is accessible
- Check BCM credentials are correctly configured
- Ensure `bcm_insecure_skip_verify` is set appropriately for your environment

**Node Discovery Issues:**

- Verify node hostnames match exactly with BCM inventory
- Check BCM API permissions for node listing
- Use `terraform output discovered_nodes` to see available nodes

**SSH Connectivity Timeouts:**

- Verify firewall rules allow SSH traffic
- Ensure BCM user was created successfully
- Check that SSH keys were properly provisioned

**Kubespray Execution Errors:**

- Verify Python 3.9+ is available on nodes
- Check Ansible logs for specific error messages
- Ensure all nodes meet minimum hardware requirements

**State Inconsistency:**

- If deployment fails mid-execution, run `terraform refresh` to sync state
- Consider `terraform destroy` and retry for clean slate

## Terraform Documentation

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
<!-- BEGIN_TF_DOCS -->

## Requirements

| Name                                                                     | Version  |
| ------------------------------------------------------------------------ | -------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | >= 1.5.0 |
| <a name="requirement_ansible"></a> [ansible](#requirement_ansible)       | ~> 1.3   |
| <a name="requirement_bcm"></a> [bcm](#requirement_bcm)                   | ~> 0.1   |
| <a name="requirement_external"></a> [external](#requirement_external)    | ~> 2.3   |
| <a name="requirement_local"></a> [local](#requirement_local)             | ~> 2.5   |
| <a name="requirement_tls"></a> [tls](#requirement_tls)                   | ~> 4.0   |

## Providers

| Name                                                            | Version |
| --------------------------------------------------------------- | ------- |
| <a name="provider_bcm"></a> [bcm](#provider_bcm)                | ~> 0.1  |
| <a name="provider_external"></a> [external](#provider_external) | ~> 2.3  |
| <a name="provider_local"></a> [local](#provider_local)          | ~> 2.5  |
| <a name="provider_tls"></a> [tls](#provider_tls)                | ~> 4.0  |

## Resources

| Name                                                                                                                                 | Type        |
| ------------------------------------------------------------------------------------------------------------------------------------ | ----------- |
| [bcm_cmuser_user.node_user](https://registry.terraform.io/providers/hashi-demo-lab/bcm/latest/docs/resources/cmuser_user)            | resource    |
| [local_file.kubespray_inventory](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file)                 | resource    |
| [local_sensitive_file.ssh_private_key](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/sensitive_file) | resource    |
| [tls_private_key.ssh_key](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key)                   | resource    |
| [bcm_cmdevice_nodes.all](https://registry.terraform.io/providers/hashi-demo-lab/bcm/latest/docs/data-sources/cmdevice_nodes)         | data source |
| [external.fetch_kubeconfig](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external)            | data source |

## Inputs

| Name                                                                                                               | Description                                                     | Type           | Default                     | Required |
| ------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------- | -------------- | --------------------------- | :------: |
| <a name="input_bcm_endpoint"></a> [bcm_endpoint](#input_bcm_endpoint)                                              | BCM API endpoint URL                                            | `string`       | `null`                      |    no    |
| <a name="input_bcm_username"></a> [bcm_username](#input_bcm_username)                                              | BCM username for authentication                                 | `string`       | `null`                      |    no    |
| <a name="input_bcm_password"></a> [bcm_password](#input_bcm_password)                                              | BCM password for authentication                                 | `string`       | `null`                      |    no    |
| <a name="input_bcm_insecure_skip_verify"></a> [bcm_insecure_skip_verify](#input_bcm_insecure_skip_verify)          | Skip TLS certificate verification                               | `bool`         | `true`                      |    no    |
| <a name="input_control_plane_nodes"></a> [control_plane_nodes](#input_control_plane_nodes)                         | List of BCM node hostnames for control plane                    | `list(string)` | `[]`                        |    no    |
| <a name="input_worker_nodes"></a> [worker_nodes](#input_worker_nodes)                                              | List of BCM node hostnames for workers                          | `list(string)` | `[]`                        |    no    |
| <a name="input_etcd_nodes"></a> [etcd_nodes](#input_etcd_nodes)                                                    | List of BCM node hostnames for etcd (defaults to control plane) | `list(string)` | `[]`                        |    no    |
| <a name="input_cluster_name"></a> [cluster_name](#input_cluster_name)                                              | Kubernetes cluster name identifier                              | `string`       | `"vsphere-k8s-cluster"`     |    no    |
| <a name="input_kubernetes_version"></a> [kubernetes_version](#input_kubernetes_version)                            | Target Kubernetes version                                       | `string`       | `"v1.28.6"`                 |    no    |
| <a name="input_cni_plugin"></a> [cni_plugin](#input_cni_plugin)                                                    | CNI plugin for pod networking                                   | `string`       | `"calico"`                  |    no    |
| <a name="input_ssh_user"></a> [ssh_user](#input_ssh_user)                                                          | SSH username for node access                                    | `string`       | `"ubuntu"`                  |    no    |
| <a name="input_ssh_private_key"></a> [ssh_private_key](#input_ssh_private_key)                                     | SSH private key (uses auto-generated if null)                   | `string`       | `null`                      |    no    |
| <a name="input_ssh_private_key_path"></a> [ssh_private_key_path](#input_ssh_private_key_path)                      | Path to SSH private key file (uses auto-generated if null)      | `string`       | `null`                      |    no    |
| <a name="input_node_username"></a> [node_username](#input_node_username)                                           | Username for BCM node account                                   | `string`       | `"ansible"`                 |    no    |
| <a name="input_node_password"></a> [node_password](#input_node_password)                                           | Password for the user account                                   | `string`       | `null`                      |    no    |
| <a name="input_node_user_full_name"></a> [node_user_full_name](#input_node_user_full_name)                         | Full name for the user account                                  | `string`       | `"Ansible Service Account"` |    no    |
| <a name="input_node_user_ssh_public_keys"></a> [node_user_ssh_public_keys](#input_node_user_ssh_public_keys)       | Additional SSH public keys                                      | `list(string)` | `[]`                        |    no    |
| <a name="input_kubespray_version"></a> [kubespray_version](#input_kubespray_version)                               | Kubespray release version                                       | `string`       | `"v2.24.0"`                 |    no    |
| <a name="input_enable_kubespray_deployment"></a> [enable_kubespray_deployment](#input_enable_kubespray_deployment) | Enable Kubespray deployment                                     | `bool`         | `true`                      |    no    |

## Outputs

| Name                                                                                                           | Description                                      |
| -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| <a name="output_discovered_nodes"></a> [discovered_nodes](#output_discovered_nodes)                            | All nodes discovered from BCM                    |
| <a name="output_control_plane_nodes"></a> [control_plane_nodes](#output_control_plane_nodes)                   | Control plane node details                       |
| <a name="output_control_plane_ips"></a> [control_plane_ips](#output_control_plane_ips)                         | IP addresses of control plane nodes              |
| <a name="output_worker_nodes"></a> [worker_nodes](#output_worker_nodes)                                        | Worker node details                              |
| <a name="output_worker_ips"></a> [worker_ips](#output_worker_ips)                                              | IP addresses of worker nodes                     |
| <a name="output_all_node_ips"></a> [all_node_ips](#output_all_node_ips)                                        | All Kubernetes node IP addresses                 |
| <a name="output_cluster_name"></a> [cluster_name](#output_cluster_name)                                        | Kubernetes cluster name                          |
| <a name="output_kubernetes_version"></a> [kubernetes_version](#output_kubernetes_version)                      | Deployed Kubernetes version                      |
| <a name="output_kubernetes_api_endpoint"></a> [kubernetes_api_endpoint](#output_kubernetes_api_endpoint)       | Kubernetes API server endpoint                   |
| <a name="output_kubespray_inventory"></a> [kubespray_inventory](#output_kubespray_inventory)                   | Generated Kubespray inventory in YAML            |
| <a name="output_ssh_user"></a> [ssh_user](#output_ssh_user)                                                    | SSH username for node access                     |
| <a name="output_ssh_public_key"></a> [ssh_public_key](#output_ssh_public_key)                                  | Generated SSH public key                         |
| <a name="output_ssh_private_key_file"></a> [ssh_private_key_file](#output_ssh_private_key_file)                | Path to generated SSH private key file           |
| <a name="output_created_users"></a> [created_users](#output_created_users)                                     | User created on BCM with SSH key configuration   |
| <a name="output_kubeconfig_ca_certificate"></a> [kubeconfig_ca_certificate](#output_kubeconfig_ca_certificate) | Base64-encoded Kubernetes cluster CA certificate |

<!-- END_TF_DOCS -->
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
