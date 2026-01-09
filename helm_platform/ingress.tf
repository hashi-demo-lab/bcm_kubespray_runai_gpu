# Ingress Controller Configuration
# Feature: Run:AI Platform Deployment
# Spec: /workspace/specs/002-runai-deployment/plan.md
# Dependency: StorageClass (for potential PVCs)

# =============================================================================
# NGINX Ingress Controller
# Requirement: Run:AI requires Kubernetes Ingress Controller
# =============================================================================

resource "kubernetes_namespace" "ingress_nginx" {
  count = var.enable_ingress_nginx ? 1 : 0

  metadata {
    name = "ingress-nginx"

    labels = {
      "app.kubernetes.io/name"    = "ingress-nginx"
      "app.kubernetes.io/part-of" = "ingress-nginx"
    }
  }
}

resource "helm_release" "ingress_nginx" {
  count = var.enable_ingress_nginx ? 1 : 0

  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.ingress_nginx_version
  namespace  = kubernetes_namespace.ingress_nginx[0].metadata[0].name

  # Service type - NodePort for on-prem without LoadBalancer
  set {
    name  = "controller.service.type"
    value = "NodePort"
  }

  # Fixed NodePort for HTTP
  set {
    name  = "controller.service.nodePorts.http"
    value = "30080"
  }

  # Fixed NodePort for HTTPS
  set {
    name  = "controller.service.nodePorts.https"
    value = "30443"
  }

  # Enable admission webhooks
  set {
    name  = "controller.admissionWebhooks.enabled"
    value = "true"
  }

  # Resource requests
  set {
    name  = "controller.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "128Mi"
  }

  depends_on = [
    kubernetes_namespace.ingress_nginx,
    helm_release.local_path_provisioner
  ]
}
