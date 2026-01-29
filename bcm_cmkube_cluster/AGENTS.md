# BCM Native Cluster Module - Agent Guide

## Purpose

This is a **reference module** that uses BCM's native `bcm_cmkube_cluster` resource to create a Kubernetes cluster. It represents BCM's built-in `cm-kubernetes-setup.conf` approach.

**This module is NOT used in the main deployment flow.** The main project uses Kubespray (root module) instead, because it provides more control over Kubernetes configuration, CNI selection, and component versions.

## When to Reference This Module

- Understanding BCM's native Kubernetes capabilities
- Comparing BCM-native vs Kubespray deployment approaches
- Looking up BCM resource data structures (`bcm_cmdevice_nodes`, `bcm_cmnet_networks`)
- Testing BCM provider API connectivity

## Key Resources

- `data.bcm_cmdevice_nodes.all` -- queries all physical nodes from BCM API
- `data.bcm_cmnet_networks.all` -- queries all networks (filters for `dgxnet`)
- `resource.bcm_cmkube_cluster.terraform` -- creates K8s cluster via BCM

## Node Filtering Pattern

BCM's `hostname_pattern` does substring matching (not regex), so filtering is done in Terraform locals:

```hcl
locals {
  master_nodes = [
    for node in data.bcm_cmdevice_nodes.all.nodes :
    node if contains(local.master_hostnames, node.hostname)
  ]
}
```

This same pattern is used in the root module's `main.tf`.

## Provider

```hcl
bcm = {
  source  = "hashi-demo-lab/bcm"
  version = "~> 0.1.3"
}
```

## Limitations vs Kubespray Approach

| Aspect | BCM Native | Kubespray (main project) |
|--------|-----------|-------------------------|
| K8s version control | Limited to BCM-supported | Any version |
| CNI selection | BCM default | Calico, Flannel, or Cilium |
| Component versions | BCM-managed | Fully customizable |
| GPU Operator integration | Separate step | Integrated via helm_platform |
| Ansible control | None | Full playbook customization |
