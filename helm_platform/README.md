# Helm Platform Module

This Terraform module deploys the complete Run:AI platform (self-hosted) with all required dependencies on a Kubernetes cluster.

## Overview

The module deploys components in the correct dependency order to support GPU workloads and Run:AI scheduling. Run:AI is deployed in **self-hosted mode** with the control plane running locally on the cluster.

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Helm Platform Module                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                    │
│   ┌─────────────────┐    ┌─────────────────┐    ┌────────────────┐ │
│   │  Storage Class  │───▶│ NGINX Ingress   │───▶│  GPU Operator  │ │
│   │  (local-path)   │    │   Controller    │    │   (v25.3.3)    │ │
│   └─────────────────┘    └─────────────────┘    └────────────────┘ │
│                                                        │           │
│   ┌─────────────────┐    ┌─────────────────┐          │           │
│   │ Metrics Server  │    │   Prometheus    │◀─────────┘           │
│   │   (v3.13.0)     │    │ Stack (v77.6.2) │                      │
│   └─────────────────┘    └─────────────────┘                      │
│                                  │                                 │
│   ┌─────────────────┐    ┌───────┴─────────┐                      │
│   │ LeaderWorkerSet │    │   Prometheus    │                      │
│   │ Operator (v0.7) │    │ Adapter (v5.1)  │                      │
│   └─────────────────┘    └─────────────────┘                      │
│           │                      │                                 │
│   ┌───────┴─────────┐           │                                 │
│   │ Knative Operator│           │                                 │
│   │    (v1.16.0)    │           │                                 │
│   └─────────────────┘           │                                 │
│           │                     │                                  │
│           └─────────┬───────────┘                                  │
│                     ▼                                              │
│          ┌────────────────────┐                                    │
│          │  Run:AI Backend   │  ◀── Phase 1: Control Plane        │
│          │  (control-plane)  │      Keycloak, PostgreSQL, Redis,  │
│          │   runai-backend   │      Thanos, Grafana, Backend      │
│          └────────────────────┘                                    │
│                     │                                              │
│                     ▼  (manual: get credentials from UI)           │
│          ┌────────────────────┐                                    │
│          │  Run:AI Cluster   │  ◀── Phase 2: Cluster Component   │
│          │  (runai-cluster)  │      Scheduler, Agent, Metrics     │
│          │    v2.21          │                                     │
│          └────────────────────┘                                    │
│                                                                    │
└─────────────────────────────────────────────────────────────────────┘
```

## Two-Phase Deployment

Run:AI self-hosted requires a two-phase deployment:

### Phase 1: Deploy Control Plane + Dependencies

```bash
cd helm_platform
terraform init
terraform apply \
  -var="runai_jfrog_token=<JFROG_TOKEN>" \
  -var="runai_admin_password=<ADMIN_PASSWORD>"
```

This deploys all dependencies and the Run:AI control plane backend. Access the UI at `https://<runai_domain>` (default: `bcm-head-01.eth.cluster`).

### Phase 2: Create Cluster in UI + Deploy Cluster Component

1. Log into the Run:AI control plane UI with `randy.keener@ibm.com`
2. Navigate to **Settings > Clusters > + New Cluster**
3. Copy the **client secret** and **cluster UID**
4. Re-run Terraform with the credentials:

```bash
terraform apply \
  -var="runai_jfrog_token=<JFROG_TOKEN>" \
  -var="runai_admin_password=<ADMIN_PASSWORD>" \
  -var="runai_client_secret=<CLIENT_SECRET>" \
  -var="runai_cluster_uid=<CLUSTER_UID>"
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
| **Knative Operator** | `knative.tf` | v1.16.0 | Serverless inference workloads |

### Run:AI Platform (Self-Hosted)

| Component | File | Chart | Namespace | Description |
|-----------|------|-------|-----------|-------------|
| **Control Plane** | `runai-backend.tf` | `control-plane` | `runai-backend` | Backend services (Keycloak, PostgreSQL, Redis, Thanos) |
| **Cluster Component** | `runai.tf` | `runai-cluster` | `runai` | AI workload scheduler and resource management |

## Usage

### Prerequisites

1. Kubernetes cluster deployed via Kubespray (root module)
2. GPU nodes with sufficient containerd storage (see [GPU_OPERATOR_PREREQUISITES.md](../docs/GPU_OPERATOR_PREREQUISITES.md))
3. NVIDIA JFrog token for Run:AI registry access

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

  # Run:AI self-hosted configuration
  runai_jfrog_token    = var.runai_jfrog_token     # From NVIDIA (sensitive)
  runai_admin_password = var.runai_admin_password   # Control plane login (sensitive)

  # Phase 2 only (after creating cluster in UI)
  runai_client_secret = var.runai_client_secret     # From control plane UI (sensitive)
  runai_cluster_uid   = var.runai_cluster_uid       # From control plane UI
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

### Run:AI Configuration (Self-Hosted)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_runai` | bool | `true` | Enable Run:AI deployment |
| `runai_jfrog_username` | string | `self-hosted-image-puller-prod` | JFrog username for registry access |
| `runai_jfrog_token` | string | `""` | JFrog token from NVIDIA (sensitive) |
| `runai_domain` | string | `bcm-head-01.eth.cluster` | FQDN for control plane and cluster access |
| `runai_admin_email` | string | `randy.keener@ibm.com` | Admin email for control plane login |
| `runai_admin_password` | string | `""` | Admin password for control plane (sensitive) |
| `runai_backend_version` | string | `2.21` | Control plane chart version |
| `runai_cluster_version` | string | `2.21` | Cluster component chart version |
| `runai_client_secret` | string | `""` | Client secret from control plane UI (sensitive) |
| `runai_cluster_uid` | string | `""` | Cluster UID from control plane UI |

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
| `knative_operator_version` | string | `v1.16.0` | Knative Operator version (Run:AI v2.21 requires Serving 1.11-1.16) |
| `enable_knative_serving` | bool | `false` | Deploy Knative Serving |

## Version Alignment

Component versions are aligned with Run:AI v2.21 system requirements and BCM `cm-kubernetes-setup.conf` configuration:

| Component | cm-kubernetes-setup.conf | This Module | Notes |
|-----------|-------------------------|-------------|-------|
| GPU Operator | v25.3.3 | v25.3.3 | v2.21 supports 24.9-25.3 |
| Prometheus Stack | v77.6.2 | v77.6.2 | |
| Prometheus Adapter | v5.1.0 | v5.1.0 | |
| Metrics Server | v3.13.0 | v3.13.0 | |
| LeaderWorkerSet | v0.7.0 | v0.7.0 | |
| Knative Operator | v1.19.2 | v1.16.0 | Downgraded: v2.21 requires Serving 1.11-1.16 |
| Run:AI Backend | 2.22.x | 2.21 | Using v2.21 per project requirements |
| Run:AI Cluster | v2.22.15 | 2.21 | Using v2.21 per project requirements |

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

### Run:AI Backend Not Starting

```bash
# Check backend pods
kubectl get pods -n runai-backend

# Check Keycloak status
kubectl logs -n runai-backend -l app=keycloakx

# Check PostgreSQL
kubectl logs -n runai-backend -l app.kubernetes.io/name=postgresql

# Verify ingress
kubectl get ingress -n runai-backend
```

### Run:AI Cluster Connection Issues

```bash
# Check cluster component pods
kubectl get pods -n runai

# Verify registry credentials
kubectl get secret runai-reg-creds -n runai -o jsonpath='{.type}'

# Check cluster agent logs
kubectl logs -n runai -l app=runai-agent
```

## Related Documentation

- [GPU Operator Prerequisites](../docs/GPU_OPERATOR_PREREQUISITES.md)
- [Scripts README](../scripts/README.md)
- [BCM cm-kubernetes-setup.conf](../cm-kubernetes-setup.conf)
- [Run:AI Self-Hosted Install Docs](https://run-ai-docs.nvidia.com/self-hosted/2.21/getting-started/installation/install-using-helm)
