# LeaderWorkerSet Operator Configuration
# Feature: Run:AI Platform Deployment
# Spec: cm-kubernetes-setup.conf - LeaderWorkerSet operator
# Dependency: Required for Run:AI SaaS distributed training workloads

# =============================================================================
# LeaderWorkerSet Namespace
# =============================================================================

resource "kubernetes_namespace" "lws" {
  count = var.enable_lws_operator ? 1 : 0

  metadata {
    name = "lws-system"

    labels = {
      "app.kubernetes.io/name" = "lws"
    }
  }
}

# =============================================================================
# LeaderWorkerSet Operator
# Manages distributed training jobs with leader-worker pattern
# =============================================================================

resource "helm_release" "lws_operator" {
  count = var.enable_lws_operator ? 1 : 0

  name       = "lws"
  # Use OCI registry format correctly
  repository = "oci://registry.k8s.io/lws/charts"
  chart      = "lws"
  version    = var.lws_operator_version
  namespace  = kubernetes_namespace.lws[0].metadata[0].name

  wait    = true
  timeout = 300 # 5 minutes

  # ==========================================================================
  # Controller Configuration
  # ==========================================================================

  values = [<<-EOT
    # Tolerations to schedule on control plane nodes
    tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule

    # Resource requests
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
  EOT
  ]

  depends_on = [
    kubernetes_namespace.lws
  ]
}
