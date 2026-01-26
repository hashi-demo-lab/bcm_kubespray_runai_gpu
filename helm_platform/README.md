# Helm Platform Module

This Terraform module deploys the complete Run:AI platform with all required dependencies on a Kubernetes cluster.

## Overview

The module deploys components in the correct dependency order to support GPU workloads and Run:AI scheduling:

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Helm Platform Module                             │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌─────────────────┐    ┌─────────────────┐    ┌────────────────┐ │
│   │  Storage Class  │───▶│ NGINX Ingress   │───▶│  GPU Operator  │ │
│   │  (local-path)   │    │   Controller    │    │   (v25.3.3)    │ │
│   └─────────────────┘    └─────────────────┘    └────────────────┘ │
│                                                        │            │
│   ┌─────────────────┐    ┌─────────────────┐          │            │
│   │ Metrics Server  │    │   Prometheus    │◀─────────┘            │
│   │   (v3.13.0)     │    │ Stack (v77.6.2) │                       │
│   └─────────────────┘    └─────────────────┘                       │
│                                  │                                  │
│   ┌─────────────────┐    ┌───────┴─────────┐                       │
│   │ LeaderWorkerSet │    │   Prometheus    │                       │
│   │ Operator (v0.7) │    │ Adapter (v5.1)  │                       │
│   └─────────────────┘    └─────────────────┘                       │
│           │                      │                                  │
│   ┌───────┴─────────┐            │                                  │
│   │ Knative Operator│            │                                  │
│   │    (v1.19.2)    │            │                                  │
│   └─────────────────┘            │                                  │
│           │                      │                                  │
│           └──────────┬───────────┘                                  │
│                      ▼                                              │
│              ┌───────────────┐                                      │
│              │    Run:AI     │                                      │
│              │  (v2.22.15)   │                                      │
│              └───────────────┘                                      │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Components

### Core Infrastructure

| Component | File | Version | Description |
|-----------|------|---------|-------------|
| **Local Path Provisioner** | `storage.tf` | v0.0.26 | Default StorageClass for persistent volumes |
| **NGINX Ingress** | `ingress.tf` | v4.9.0 | Kubernetes ingress controller (NodePort 30080/30443) |

### GPU Support

| Component | File | Version | Description |
|-----------|------|---------|-------------|
| **NVIDIA GPU Operator** | `gpu-operator.tf` | v25.3.3 | GPU drivers, device plugin, toolkit, metrics |

### Monitoring Stack

| Component | File | Version | Description |
|-----------|------|---------|-------------|
| **kube-prometheus-stack** | `prometheus.tf` | v77.6.2 | Prometheus, Grafana, Alertmanager |
| **Prometheus Adapter** | `prometheus-adapter.tf` | v5.1.0 | Custom metrics API for HPA |
| **Metrics Server** | `metrics-server.tf` | v3.13.0 | Resource metrics (CPU/memory) |

### Run:AI Dependencies

| Component | File | Version | Description |
|-----------|------|---------|-------------|
| **LeaderWorkerSet Operator** | `lws.tf` | v0.7.0 | Distributed training job orchestration |
| **Knative Operator** | `knative.tf` | v1.19.2 | Serverless inference workloads |

### Run:AI Platform

| Component | File | Version | Description |
|-----------|------|---------|-------------|
| **Run:AI Cluster** | `runai.tf` | v2.22.15 | AI workload scheduler and resource management |

## Usage

### Prerequisites

1. Kubernetes cluster deployed via Kubespray (root module)
2. GPU nodes with sufficient containerd storage (see [GPU_OPERATOR_PREREQUISITES.md](../docs/GPU_OPERATOR_PREREQUISITES.md))
3. Run:AI credentials (token and cluster UID from Run:AI console)

### Basic Configuration

```hcl
module "helm_platform" {
  source = "./helm_platform"

  # Kubernetes connection (from root module outputs)
  kubernetes_host               = data.terraform_remote_state.infrastructure.outputs.kubernetes_api_endpoint
  kubernetes_ca_certificate     = data.terraform_remote_state.infrastructure.outputs.kubeconfig_ca_certificate
  kubernetes_client_certificate = data.terraform_remote_state.infrastructure.outputs.kubeconfig_client_certificate
  kubernetes_client_key         = data.terraform_remote_state.infrastructure.outputs.kubeconfig_client_key

  # Cluster metadata
  cluster_name     = "bcm-k8s-cluster"
  control_plane_ip = "10.184.162.103"

  # Run:AI configuration (obtain from Run:AI console)
  runai_cluster_token = var.runai_cluster_token  # Sensitive
  runai_cluster_uid   = var.runai_cluster_uid
  runai_cluster_url   = "runai.example.com"
}
```

### DGX Node Configuration

For DGX systems with pre-installed NVIDIA drivers and toolkit:

```hcl
# Disable container-based driver/toolkit installation
gpu_driver_enabled  = false
gpu_toolkit_enabled = false
```

For non-DGX systems that need driver installation:

```hcl
# Enable container-based driver/toolkit installation
gpu_driver_enabled  = true
gpu_toolkit_enabled = true
gpu_driver_version  = "550.54.15"
```

### Selective Component Deployment

```hcl
# Disable components not needed
enable_gpu_operator       = true
enable_prometheus         = true
enable_prometheus_adapter = true
enable_metrics_server     = true
enable_lws_operator       = true
enable_knative_operator   = true
enable_runai              = true
enable_ingress_nginx      = true
enable_local_storage      = true
enable_grafana            = true
```

## Variables Reference

### Kubernetes Connection

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `kubernetes_host` | string | Yes | Kubernetes API endpoint URL |
| `kubernetes_ca_certificate` | string | Yes | Base64-encoded cluster CA certificate |
| `kubernetes_client_certificate` | string | Yes | Base64-encoded client certificate |
| `kubernetes_client_key` | string | Yes | Base64-encoded client private key |

### Run:AI Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_runai` | bool | `true` | Enable Run:AI deployment |
| `runai_version` | string | `2.22.15` | Run:AI cluster-installer version |
| `runai_cluster_name` | string | `bcm-k8s-cluster` | Cluster name in Run:AI console |
| `runai_cluster_url` | string | `runai.hashicorp.local` | FQDN for cluster access |
| `runai_control_plane_url` | string | `https://app.run.ai` | Run:AI SaaS URL |
| `runai_cluster_token` | string | `""` | Cluster authentication token (sensitive) |
| `runai_cluster_uid` | string | `""` | Cluster UID from console |

### GPU Operator Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_gpu_operator` | bool | `true` | Enable GPU Operator deployment |
| `gpu_operator_version` | string | `v25.3.3` | GPU Operator Helm chart version |
| `gpu_driver_enabled` | bool | `true` | Install drivers via containers |
| `gpu_driver_version` | string | `550.54.15` | NVIDIA driver version |
| `gpu_toolkit_enabled` | bool | `true` | Install container toolkit |

### Prometheus Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_prometheus` | bool | `true` | Enable kube-prometheus-stack |
| `prometheus_stack_version` | string | `77.6.2` | Prometheus stack version |
| `enable_grafana` | bool | `true` | Enable Grafana |
| `grafana_admin_password` | string | `admin` | Grafana admin password (sensitive) |
| `enable_prometheus_adapter` | bool | `true` | Enable Prometheus Adapter |
| `prometheus_adapter_version` | string | `5.1.0` | Prometheus Adapter version |
| `enable_metrics_server` | bool | `true` | Enable Metrics Server |
| `metrics_server_version` | string | `3.13.0` | Metrics Server version |

### Operator Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_lws_operator` | bool | `true` | Enable LeaderWorkerSet Operator |
| `lws_operator_version` | string | `v0.7.0` | LWS Operator version |
| `enable_knative_operator` | bool | `true` | Enable Knative Operator |
| `knative_operator_version` | string | `v1.19.2` | Knative Operator version |
| `enable_knative_serving` | bool | `false` | Deploy Knative Serving |

## Outputs

| Output | Description |
|--------|-------------|
| `prometheus_namespace` | Prometheus namespace name |
| `prometheus_service_name` | Prometheus service for Run:AI integration |

## Version Alignment

Component versions are aligned with BCM `cm-kubernetes-setup.conf` configuration:

| Component | cm-kubernetes-setup.conf | This Module |
|-----------|-------------------------|-------------|
| GPU Operator | v25.3.3 | v25.3.3 ✅ |
| Prometheus Stack | v77.6.2 | v77.6.2 ✅ |
| Prometheus Adapter | v5.1.0 | v5.1.0 ✅ |
| Metrics Server | v3.13.0 | v3.13.0 ✅ |
| LeaderWorkerSet | v0.7.0 | v0.7.0 ✅ |
| Knative Operator | v1.19.2 | v1.19.2 ✅ |
| Run:AI | v2.22.15 | v2.22.15 ✅ |

## Troubleshooting

### GPU Operator Pods Not Starting

```bash
# Check GPU Operator namespace
kubectl get pods -n gpu-operator

# Check driver daemon logs
kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset

# Verify GPU detection
kubectl describe nodes | grep -A5 "Capacity:" | grep nvidia
```

### Prometheus Not Scraping GPU Metrics

```bash
# Verify DCGM exporter is running
kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter

# Check Prometheus targets
kubectl port-forward -n prometheus svc/kube-prometheus-stack-prometheus 9090:9090
# Visit http://localhost:9090/targets
```

### Run:AI Connection Issues

```bash
# Check Run:AI pods
kubectl get pods -n runai

# Verify cluster token is set
kubectl get secret -n runai

# Check cluster connection
kubectl logs -n runai -l app=runai-cluster-controller
```

## Related Documentation

- [GPU Operator Prerequisites](../docs/GPU_OPERATOR_PREREQUISITES.md)
- [Scripts README](../scripts/README.md)
- [BCM cm-kubernetes-setup.conf](../cm-kubernetes-setup.conf)
