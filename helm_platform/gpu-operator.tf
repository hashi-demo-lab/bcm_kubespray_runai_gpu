# NVIDIA GPU Operator Configuration
# Feature: Run:AI Platform Deployment
# Spec: cm-kubernetes-setup.conf - NVIDIA GPU Operator
# Version aligned with BCM configuration

# =============================================================================
# NVIDIA GPU Operator
# Deploys GPU drivers, device plugin, container toolkit, and monitoring
# =============================================================================

# Import existing namespace if it exists, or create new
# To import: terraform import 'kubernetes_namespace.gpu_operator[0]' gpu-operator
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

  lifecycle {
    # Prevent destruction if namespace has resources
    prevent_destroy = false
    # Ignore changes to labels made externally
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
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
  # Configuration aligned with cm-kubernetes-setup.conf
  # ==========================================================================

  values = [<<-EOT
    # Driver Configuration
    # DGX systems have drivers pre-installed, set to false for DGX
    # Set to true for non-DGX systems that need driver installation
    driver:
      enabled: ${var.gpu_driver_enabled}
      version: "${var.gpu_driver_version}"
      rdma:
        enabled: false

    # Container Toolkit
    # DGX systems have toolkit pre-installed, set to false for DGX
    toolkit:
      enabled: ${var.gpu_toolkit_enabled}

    # Container Device Interface (CDI)
    cdi:
      enabled: true
      default: false

    # DCGM (standalone) - disabled, use dcgmExporter instead
    dcgm:
      enabled: false

    # DCGM Exporter for GPU Metrics
    dcgmExporter:
      enabled: true
      serviceMonitor:
        enabled: ${var.enable_prometheus}

    # Node Feature Discovery
    nfd:
      enabled: true

    # Device Plugin
    devicePlugin:
      enabled: true
      env:
        - name: DEVICE_LIST_STRATEGY
          value: volume-mounts

    # MIG Configuration
    mig:
      strategy: single

    # MIG Manager
    migManager:
      enabled: true

    # GPU Feature Discovery
    gfd:
      enabled: true

    # Kata Manager (disabled)
    kataManager:
      enabled: false

    # Sandbox Workloads (disabled)
    sandboxWorkloads:
      enabled: false

    # Validator configuration
    validator:
      driver:
        env:
          - name: DISABLE_DEV_CHAR_SYMLINK_CREATION
            value: "true"
  EOT
  ]

  depends_on = [
    kubernetes_namespace.gpu_operator
  ]
}
