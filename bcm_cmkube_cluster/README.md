# BCM Kubernetes Cluster Terraform Configuration

This Terraform configuration manages a Bright Cluster Manager (BCM) Kubernetes cluster based on the settings from `cm-kubernetes-setup.conf`.

## Overview

This configuration creates a production-grade Kubernetes cluster with:
- **3 Master Nodes**: `cpu-03`, `cpu-05`, `cpu-06` (control plane)
- **2 Worker Nodes**: `dgx-05`, `dgx-06` (GPU workloads)
- **3 Etcd Nodes**: `cpu-03`, `cpu-05`, `cpu-06` (dedicated HA etcd cluster)
- **Kubernetes Version**: 1.32
- **CNI Plugin**: Calico
- **Pod Network**: 172.29.0.0/16
- **Service Network**: 10.150.0.0/16

## Configuration Source

This Terraform code is generated from the BCM configuration file:
```
cm-kubernetes-setup.conf
```

Key configuration mappings:
- `kc.name: terraform` → `cluster_name = "terraform"`
- `kc.version: '1.32'` → `kubernetes_version = "1.32"`
- `kc.network_plugin: calico` → `cni_plugin = "calico"`
- `master.nodes` → `master_nodes` data source filter
- `worker.nodes` → `worker_nodes` data source filter
- `etcd.nodes` → `etcd_nodes` data source filter

## Prerequisites

1. **BCM Provider Configuration**: Configure the BCM provider with appropriate credentials
2. **Node Availability**: Ensure the following nodes are available in BCM:
   - Master nodes: `cpu-03`, `cpu-05`, `cpu-06`
   - Worker nodes: `dgx-05`, `dgx-06`
3. **Network Configuration**: At least one management network must be available
4. **BCM Version**: BCM 10.0 or later (based on config file metadata)

## File Structure

```
bcm_cmkube_cluster/
├── main.tf                    # Main cluster resource and data sources
├── variables.tf               # Input variables with validation
├── outputs.tf                 # Cluster outputs and metadata
├── terraform.tfvars.example   # Example variable values
└── README.md                  # This file
```

## Usage

### 1. Configure Variables

Copy the example variables file:
```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` to customize your deployment (or use defaults from cm-kubernetes-setup.conf).

### 2. Initialize Terraform

```bash
terraform init
```

### 3. Plan the Deployment

```bash
terraform plan
```

Review the plan carefully to ensure:
- Correct number of master nodes (3)
- Correct number of worker nodes (2)
- Correct number of etcd nodes (3)
- Appropriate Kubernetes version (1.32)

### 4. Apply the Configuration

```bash
terraform apply
```

Confirm the changes when prompted.

### 5. Verify the Cluster

After successful deployment, view the cluster details:
```bash
terraform output
```

## Important Configuration Notes

### High Availability (HA)

This configuration implements HA best practices:
- **3 master nodes**: Provides control plane redundancy
- **3 dedicated etcd nodes**: Ensures etcd quorum (recommended for production)
- **2 worker nodes**: Minimum for workload distribution

### Node Selection

The configuration uses data sources with hostname patterns:
- Masters: `cpu-0[356]` matches cpu-03, cpu-05, cpu-06
- Workers: `dgx-0[56]` matches dgx-05, dgx-06
- Etcd: `cpu-0[356]` matches cpu-03, cpu-05, cpu-06

If your nodes have different naming patterns, update the `hostname_pattern` in `main.tf`.

### CNI Plugin

The configuration uses Calico (from `network_plugin: calico` in config). Calico provides:
- Network policy enforcement
- IPAM (IP Address Management)
- BGP support for on-premises networking

### Network Configuration

From cm-kubernetes-setup.conf:
- **Pod Network**: 172.29.0.0/16 (kube-terraform-pod)
- **Service Network**: 10.150.0.0/16 (kube-terraform-service)
- **Cluster Domain**: cluster.local

## Variables

| Variable | Description | Default | Source |
|----------|-------------|---------|--------|
| `cluster_name` | Kubernetes cluster name | `"terraform"` | `kc.name` |
| `kubernetes_version` | Kubernetes version | `"1.32"` | `kc.version` |
| `cni_plugin` | CNI plugin | `"calico"` | `kc.network_plugin` |
| `pod_network_cidr` | Pod network CIDR | `"172.29.0.0/16"` | `networks.pod.base/bits` |
| `service_network_cidr` | Service network CIDR | `"10.150.0.0/16"` | `networks.service.base/bits` |
| `cluster_domain` | Cluster domain | `"cluster.local"` | `kc.domain` |
| `external_fqdn` | External FQDN | `"bcm-head-01.eth.cluster"` | `kc.external_fqdn` |
| `force_bypass_validation` | Bypass validation | `false` | - |
| `prevent_destroy` | Prevent accidental deletion | `true` | - |

## Outputs

The configuration provides comprehensive outputs:

### Cluster Information
- `cluster_id` / `cluster_uuid`: Cluster identifiers
- `cluster_name`: Cluster name
- `cluster_version`: Kubernetes version
- `cluster_creation_time`: Creation timestamp

### Node Counts
- `master_node_count`: Number of master nodes (expected: 3)
- `worker_node_count`: Number of worker nodes (expected: 2)
- `etcd_node_count`: Number of etcd nodes (expected: 3)

### Discovery Information
- `discovered_masters`: List of discovered master nodes
- `discovered_workers`: List of discovered worker nodes
- `discovered_etcd`: List of discovered etcd nodes

## Import Existing Cluster

If the cluster already exists in BCM, you can import it:

```bash
# Get the cluster UUID from BCM
terraform import bcm_cmkube_cluster.terraform <cluster-uuid>
```

The import command is also provided as an output after cluster creation.

## Safety Features

### Lifecycle Protection
The configuration includes `prevent_destroy = true` by default to prevent accidental cluster deletion. To destroy the cluster:

1. Set `prevent_destroy = false` in `terraform.tfvars`
2. Run `terraform apply` to update the lifecycle rule
3. Run `terraform destroy` to remove the cluster

### Validation
- Cluster name validation: Only alphanumeric, hyphens, and underscores
- Kubernetes version validation: Must be in format 'X.Y'
- CNI plugin validation: Must be calico, flannel, or weave
- Node count validation: Data sources validate minimum node requirements

## Troubleshooting

### No Nodes Found
If the data sources return no nodes:
1. Verify node names match the hostname patterns in `main.tf`
2. Check that nodes are registered in BCM
3. Review BCM provider configuration

### Version Mismatch
If the Kubernetes version is not available:
1. Check BCM supported Kubernetes versions
2. Update `kubernetes_version` variable to a supported version
3. Consult BCM documentation for version compatibility

### Network Configuration Issues
If management network is not found:
1. Verify networks exist in BCM using `data.bcm_cmnet_networks.all`
2. Check network configuration in BCM
3. Manually specify `management_network` in `main.tf`

## Related Documentation

- [BCM Kubernetes Setup Documentation](https://www.nvidia.com/en-us/data-center/bright-cluster-manager/)
- [Terraform BCM Provider](https://registry.terraform.io/providers/hashi-demo-lab/bcm/latest/docs)
- [cm-kubernetes-setup.conf Reference](../cm-kubernetes-setup.conf)

## Configuration Mappings

### From cm-kubernetes-setup.conf to Terraform

| Config Path | Config Value | Terraform Variable |
|-------------|--------------|-------------------|
| `meta.hostname` | `bcm-head-01` | - |
| `meta.date` | `Thu Jan 8 21:54:06 2026` | - |
| `kc.name` | `terraform` | `cluster_name` |
| `kc.version` | `1.32` | `kubernetes_version` |
| `kc.network_plugin` | `calico` | `cni_plugin` |
| `kc.domain` | `cluster.local` | `cluster_domain` |
| `kc.external_fqdn` | `bcm-head-01.eth.cluster` | `external_fqdn` |
| `master.nodes` | `[cpu-03, cpu-05, cpu-06]` | `master_nodes` (via data source) |
| `worker.nodes` | `[dgx-05, dgx-06]` | `worker_nodes` (via data source) |
| `etcd.nodes` | `[cpu-03, cpu-05, cpu-06]` | `etcd_nodes` (via data source) |
| `networks.pod.base` | `172.29.0.0` | `pod_network_cidr` |
| `networks.pod.bits` | `16` | `pod_network_cidr` |
| `networks.service.base` | `10.150.0.0` | `service_network_cidr` |
| `networks.service.bits` | `16` | `service_network_cidr` |

## Additional Features from Config

The following features from `cm-kubernetes-setup.conf` are configured at the BCM level and inherited by this cluster:

### Operators (from config)
- Kubernetes Dashboard (enabled)
- Kubernetes Metrics Server (enabled)
- Kubernetes State Metrics (enabled)
- MetalLB (enabled)
- NVIDIA GPU Operator (enabled)
- Prometheus Operator Stack (optional)
- Grafana Loki (optional)
- Run:ai (optional)

### Ingress Configuration
- Ingress Controller: Nginx (enabled)
- HTTPS Port: 30443
- HTTP Port: 30080
- Certificates: Provided (`cert_provided: true`)

### Container Runtime
- Runtime: containerd
- Packages: cm-containerd

### NVIDIA Configuration
- GPU Support: false (as configured)
- Toolkit Package: nvidia-container-toolkit

These features are managed through BCM's cluster configuration and operator deployment mechanisms, not directly through this Terraform resource.

## Maintenance

### Updating the Cluster
To update cluster configuration:
1. Modify variables in `terraform.tfvars`
2. Run `terraform plan` to preview changes
3. Run `terraform apply` to apply changes

### Upgrading Kubernetes Version
To upgrade the Kubernetes version:
1. Update `kubernetes_version` in `terraform.tfvars`
2. Ensure the new version is supported by BCM
3. Plan and apply the change carefully in a maintenance window

### Adding/Removing Nodes
To modify node membership:
1. Update hostname patterns in `main.tf` data sources
2. Ensure nodes are available in BCM
3. Plan and apply the changes

## Support

For issues related to:
- **Terraform Configuration**: Review this README and Terraform documentation
- **BCM Provider**: Check the BCM provider documentation
- **Cluster Operations**: Consult BCM documentation and support
- **Kubernetes**: Refer to Kubernetes documentation
