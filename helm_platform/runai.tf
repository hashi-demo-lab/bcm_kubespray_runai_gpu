# Run:AI Cluster Configuration
# Feature: Run:AI Platform Deployment
# Spec: cm-kubernetes-setup.conf - Run:ai (SaaS)
# Dependencies: GPU Operator, Prometheus Stack, Prometheus Adapter,
#               LeaderWorkerSet Operator, Knative Operator, Ingress

# =============================================================================
# Run:AI Namespace
# =============================================================================

resource "kubernetes_namespace" "runai" {
  count = var.enable_runai ? 1 : 0

  metadata {
    name = "runai"

    labels = {
      "app.kubernetes.io/name"             = "runai"
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

# =============================================================================
# TLS Certificate for Run:AI
# =============================================================================

# Generate self-signed certificate if not provided
resource "tls_private_key" "runai" {
  count = var.enable_runai && var.generate_self_signed_cert ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "runai" {
  count = var.enable_runai && var.generate_self_signed_cert ? 1 : 0

  private_key_pem = tls_private_key.runai[0].private_key_pem

  subject {
    common_name  = var.runai_cluster_url
    organization = "Run:AI Cluster"
  }

  dns_names = [
    var.runai_cluster_url,
    "*.${var.runai_cluster_url}",
    "localhost"
  ]

  ip_addresses = [
    local.control_plane_ip,
    "127.0.0.1"
  ]

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth"
  ]
}

# Create TLS secret for Run:AI
resource "kubernetes_secret" "runai_tls" {
  count = var.enable_runai ? 1 : 0

  metadata {
    name      = "runai-cluster-domain-tls-secret"
    namespace = kubernetes_namespace.runai[0].metadata[0].name
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = var.generate_self_signed_cert ? tls_self_signed_cert.runai[0].cert_pem : var.runai_tls_cert
    "tls.key" = var.generate_self_signed_cert ? tls_private_key.runai[0].private_key_pem : var.runai_tls_key
  }

  depends_on = [
    kubernetes_namespace.runai
  ]
}

# =============================================================================
# Run:AI Cluster Installation via Helm
# Only deploys if cluster token is provided
# =============================================================================

resource "helm_release" "runai_cluster" {
  count = var.enable_runai && var.runai_cluster_token != "" ? 1 : 0

  name       = "cluster-installer"
  repository = "https://runai.jfrog.io/artifactory/run-ai-charts"
  chart      = "cluster-installer"
  version    = var.runai_version
  namespace  = kubernetes_namespace.runai[0].metadata[0].name

  wait    = true
  timeout = 900 # 15 minutes (increased for cluster-installer)

  # ==========================================================================
  # Control Plane Connection
  # ==========================================================================

  set {
    name  = "controlPlane.url"
    value = var.runai_control_plane_url
  }

  # ==========================================================================
  # Cluster Identification
  # ==========================================================================

  set {
    name  = "cluster.uid"
    value = var.runai_cluster_uid
  }

  set_sensitive {
    name  = "cluster.token"
    value = var.runai_cluster_token
  }

  set {
    name  = "cluster.name"
    value = var.runai_cluster_name
  }

  set {
    name  = "cluster.url"
    value = "https://${var.runai_cluster_url}"
  }

  # ==========================================================================
  # TLS Configuration
  # ==========================================================================

  set {
    name  = "cluster.tlsSecret"
    value = kubernetes_secret.runai_tls[0].metadata[0].name
  }

  # ==========================================================================
  # Disable Bundled Components (we deploy separately)
  # ==========================================================================

  # GPU Operator - deployed separately
  set {
    name  = "gpu-operator.enabled"
    value = "false"
  }

  # Prometheus - deployed separately via kube-prometheus-stack
  set {
    name  = "prometheus.enabled"
    value = "false"
  }

  set {
    name  = "prometheus.install"
    value = "false"
  }

  # ==========================================================================
  # Use Our Prometheus Instance
  # ==========================================================================

  set {
    name  = "prometheus.prometheusServiceName"
    value = "kube-prometheus-stack-prometheus"
  }

  set {
    name  = "prometheus.prometheusServiceNamespace"
    value = "prometheus"
  }

  # ==========================================================================
  # Ingress Configuration
  # ==========================================================================

  set {
    name  = "ingress.enabled"
    value = "true"
  }

  set {
    name  = "ingress.ingressClassName"
    value = "nginx"
  }

  set {
    name  = "ingress.host"
    value = var.runai_cluster_url
  }

  set {
    name  = "ingress.tlsSecretName"
    value = kubernetes_secret.runai_tls[0].metadata[0].name
  }

  # ==========================================================================
  # All dependencies must be ready before Run:AI installation
  # ==========================================================================

  depends_on = [
    kubernetes_namespace.runai,
    kubernetes_secret.runai_tls,
    helm_release.gpu_operator,
    helm_release.ingress_nginx,
    helm_release.prometheus_stack,
    helm_release.prometheus_adapter,
    helm_release.lws_operator,
    helm_release.knative_operator
  ]
}
