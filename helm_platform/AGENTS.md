# Helm Platform Module - Agent Guide

## Purpose

This child module deploys the complete Run:AI v2.21 self-hosted platform with all dependencies via Helm charts on an existing Kubernetes cluster.

## Component Dependency Order

Components must deploy in this order. Each line depends on what's above it:

```
1. local-path-provisioner (storage.tf)     -- default StorageClass
2. NGINX Ingress Controller (ingress.tf)   -- NodePort 30080/30443
3. NVIDIA GPU Operator (gpu-operator.tf)   -- drivers, device plugin, DCGM
4. kube-prometheus-stack (prometheus.tf)    -- Prometheus, Alertmanager, Grafana
   ├── Prometheus Adapter (prometheus-adapter.tf)  -- custom metrics API
   └── Metrics Server (metrics-server.tf)          -- CPU/memory metrics
5. LeaderWorkerSet Operator (lws.tf)       -- distributed training jobs
6. Knative Operator (knative.tf)           -- serverless inference
7. Run:AI Backend (runai-backend.tf)       -- control plane (Phase 1)
8. Run:AI Cluster (runai.tf)               -- scheduler + agent (Phase 2)
```

## Version Pinning

All versions aligned with Run:AI v2.21 system requirements:

| Component | Version | Chart Repo | Namespace |
|-----------|---------|------------|-----------|
| local-path-provisioner | v0.0.26 | GitHub raw manifest | local-path-storage |
| NGINX Ingress | v4.9.0 | https://kubernetes.github.io/ingress-nginx | ingress-nginx |
| GPU Operator | v25.3.3 | https://helm.ngc.nvidia.com/nvidia | gpu-operator |
| kube-prometheus-stack | v77.6.2 | https://prometheus-community.github.io/helm-charts | prometheus |
| Prometheus Adapter | v5.1.0 | prometheus-community | prometheus |
| Metrics Server | v3.13.0 | https://kubernetes-sigs.github.io/metrics-server | kube-system |
| LeaderWorkerSet | v0.7.0 | GitHub release manifest | leaderworker-system |
| Knative Operator | v1.16.0 | GitHub release manifest | knative-operator |
| Run:AI Backend | 2.21 | runai.jfrog.io/cp-charts-prod | runai-backend |
| Run:AI Cluster | 2.21 | runai.jfrog.io/cp-charts-prod | runai |

### Version Compatibility Notes

- **Knative**: BCM cm-kubernetes-setup.conf uses v1.19.2, but Run:AI v2.21 requires Knative Serving 1.11-1.16. We use v1.16.0.
- **GPU Operator**: Run:AI v2.21 supports GPU Operator v24.9-25.3. We use v25.3.3.
- **Kubernetes**: Run:AI v2.21 requires K8s 1.30-1.32. Cluster deploys v1.31.9.

## Two-Phase Run:AI Deployment

Run:AI self-hosted requires manual intervention between phases:

### Phase 1: Deploy Backend (Control Plane)
```bash
terraform apply -var="runai_jfrog_token=<TOKEN>" -var="runai_admin_password=<PASS>"
```
Deploys: Keycloak, PostgreSQL, Redis, Thanos, Grafana, Backend services

### Phase 2: Create Cluster in UI, Then Deploy Cluster Component
1. Access UI at `https://bcm-head-01.eth.cluster` (via NodePort 30443)
2. Log in with `randy.keener@ibm.com`
3. Navigate to Settings > Clusters > + New Cluster
4. Copy the **client secret** and **cluster UID**
5. Re-run with credentials:
```bash
terraform apply \
  -var="runai_jfrog_token=<TOKEN>" \
  -var="runai_admin_password=<PASS>" \
  -var="runai_client_secret=<SECRET>" \
  -var="runai_cluster_uid=<UID>"
```

## Helm Chart Sources

- **NVIDIA charts**: https://helm.ngc.nvidia.com/nvidia
- **Run:AI charts**: Private JFrog registry (requires `runai_jfrog_token`)
- **Bitnami** (PostgreSQL, Redis): https://charts.bitnami.com/bitnami
- **Prometheus community**: https://prometheus-community.github.io/helm-charts
- **Kubernetes SIGs**: metrics-server, ingress-nginx

## Toggle Variables

Every component can be individually enabled/disabled:

```hcl
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
enable_knative_serving    = false  # Deployed by operator, not directly
```

## Known Issues and Workarounds

### NGINX Ingress healthcheck port conflict
The NGINX proxy healthcheck was changed to port 8082 to avoid conflicts with BCM services. See commit `f5b7b34`.

### DGX containerd disk space
DGX nodes have small `/var` partitions (~6GB). GPU driver images are ~3GB. Must relocate containerd to `/local` before GPU Operator install:
```bash
./scripts/relocate-containerd.sh dgx-05 /local
```

### Helm NFS file locking
Control plane nodes use NFS home directories. Helm fails with "no locks available". Fix:
```bash
source ./scripts/setup-helm-nfs.sh
```

### GPU driver configuration for DGX
- DGX with pre-installed drivers: `gpu_driver_enabled = false`, `gpu_toolkit_enabled = false`
- DGX without drivers (BCM-provisioned): `gpu_driver_enabled = true`, `gpu_toolkit_enabled = true`

## Debugging Commands

```bash
# Check all platform pods
kubectl get pods -A | grep -E "gpu-operator|ingress|prometheus|runai|knative|lws|metrics"

# GPU Operator status
kubectl get pods -n gpu-operator
kubectl logs -n gpu-operator -l app=nvidia-driver-daemonset

# Run:AI Backend
kubectl get pods -n runai-backend
kubectl logs -n runai-backend -l app=keycloakx

# Run:AI Cluster
kubectl get pods -n runai
kubectl logs -n runai -l app=runai-agent

# Verify GPU detection
kubectl describe nodes | grep -A5 "Capacity:" | grep nvidia
```
