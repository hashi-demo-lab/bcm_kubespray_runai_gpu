# Knative Operator Configuration
# Feature: Run:AI Platform Deployment
# Spec: cm-kubernetes-setup.conf - Knative Operator
# Dependency: Required for Run:AI self-hosted serverless inference workloads

# =============================================================================
# Knative Operator Namespace
# =============================================================================

resource "kubernetes_namespace" "knative_operator" {
  count = var.enable_knative_operator ? 1 : 0

  metadata {
    name = "knative-operator"

    labels = {
      "app.kubernetes.io/name" = "knative-operator"
    }
  }
}

# =============================================================================
# Knative Operator
# Manages Knative Serving and Eventing components
# =============================================================================

resource "helm_release" "knative_operator" {
  count = var.enable_knative_operator ? 1 : 0

  name       = "knative-operator"
  repository = "https://knative.github.io/operator"
  chart      = "knative-operator"
  version    = var.knative_operator_version
  namespace  = kubernetes_namespace.knative_operator[0].metadata[0].name

  wait    = true
  timeout = 600 # 10 minutes

  # ==========================================================================
  # Operator Configuration
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
  EOT
  ]

  depends_on = [
    kubernetes_namespace.knative_operator
  ]
}

# =============================================================================
# Knative Serving (Optional - deployed by operator if enabled)
# =============================================================================

resource "kubernetes_namespace" "knative_serving" {
  count = var.enable_knative_operator && var.enable_knative_serving ? 1 : 0

  metadata {
    name = "knative-serving"

    labels = {
      "app.kubernetes.io/name" = "knative-serving"
    }
  }

  depends_on = [
    helm_release.knative_operator
  ]
}
