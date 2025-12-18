# NVIDIA GPU Operator Configuration
# Feature: Run:AI Platform Deployment
# Spec: /workspace/specs/002-runai-deployment/plan.md

# =============================================================================
# NVIDIA GPU Operator
# Deploys GPU drivers, device plugin, container toolkit, and monitoring
# =============================================================================

resource "kubernetes_namespace" "gpu_operator" {
  count = var.enable_gpu_operator ? 1 : 0

  metadata {
    name = "gpu-operator"

    labels = {
      # Pod Security Admission - GPU Operator requires privileged
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "helm_release" "gpu_operator" {
  count = var.enable_gpu_operator ? 1 : 0

  name       = "gpu-operator"
  repository = "https://helm.ngc.nvidia.com/nvidia"
  chart      = "gpu-operator"
  version    = var.gpu_operator_version
  namespace  = kubernetes_namespace.gpu_operator[0].metadata[0].name

  # Wait for deployment - GPU driver installation takes time
  wait    = true
  timeout = 900 # 15 minutes

  # ==========================================================================
  # Driver Configuration
  # ==========================================================================

  set {
    name  = "driver.enabled"
    value = tostring(var.gpu_driver_enabled)
  }

  set {
    name  = "driver.version"
    value = var.gpu_driver_version
  }

  # ==========================================================================
  # NVIDIA Container Toolkit
  # ==========================================================================

  set {
    name  = "toolkit.enabled"
    value = "true"
  }

  # ==========================================================================
  # Container Device Interface (CDI)
  # Recommended for newer Kubernetes setups
  # ==========================================================================

  set {
    name  = "cdi.enabled"
    value = "true"
  }

  set {
    name  = "cdi.default"
    value = "true"
  }

  # ==========================================================================
  # DCGM Exporter for GPU Metrics
  # ==========================================================================

  set {
    name  = "dcgmExporter.enabled"
    value = "true"
  }

  set {
    name  = "dcgmExporter.serviceMonitor.enabled"
    value = "false"
  }

  # ==========================================================================
  # Node Feature Discovery
  # Auto-labels GPU nodes
  # ==========================================================================

  set {
    name  = "nfd.enabled"
    value = "true"
  }

  # ==========================================================================
  # Device Plugin
  # ==========================================================================

  set {
    name  = "devicePlugin.enabled"
    value = "true"
  }

  # ==========================================================================
  # MIG Configuration (Multi-Instance GPU)
  # ==========================================================================

  set {
    name  = "mig.strategy"
    value = "single"
  }

  # ==========================================================================
  # GFD (GPU Feature Discovery)
  # ==========================================================================

  set {
    name  = "gfd.enabled"
    value = "true"
  }

  depends_on = [
    kubernetes_namespace.gpu_operator
  ]
}
