# Prometheus Adapter Configuration
# Feature: Run:AI Platform Deployment
# Spec: cm-kubernetes-setup.conf - Prometheus Adapter
# Dependency: Required for Run:AI custom metrics

# =============================================================================
# Prometheus Adapter
# Enables custom metrics API for Kubernetes HPA based on Prometheus metrics
# =============================================================================

resource "helm_release" "prometheus_adapter" {
  count = var.enable_prometheus_adapter ? 1 : 0

  name       = "prometheus-adapter"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-adapter"
  version    = var.prometheus_adapter_version
  namespace  = var.enable_prometheus ? kubernetes_namespace.prometheus[0].metadata[0].name : "prometheus"

  wait    = true
  timeout = 300 # 5 minutes

  # ==========================================================================
  # Prometheus Connection
  # ==========================================================================

  set {
    name  = "prometheus.url"
    value = "http://kube-prometheus-stack-prometheus.prometheus.svc"
  }

  set {
    name  = "prometheus.port"
    value = "9090"
  }

  # ==========================================================================
  # RBAC Configuration
  # ==========================================================================

  set {
    name  = "rbac.create"
    value = "true"
  }

  # ==========================================================================
  # Resource Configuration
  # ==========================================================================

  set {
    name  = "resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "resources.requests.memory"
    value = "128Mi"
  }

  # ==========================================================================
  # Tolerations for Control Plane
  # ==========================================================================

  values = [<<-EOT
    tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
  EOT
  ]

  depends_on = [
    helm_release.prometheus_stack
  ]
}
