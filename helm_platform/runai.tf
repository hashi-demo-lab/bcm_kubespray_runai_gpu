# Run:AI Cluster Component (Self-Hosted)
# Feature: Run:AI Platform Deployment
# Spec: cm-kubernetes-setup.conf - Run:ai (SaaS) chart used as cluster component
# Docs: https://run-ai-docs.nvidia.com/self-hosted/2.21/getting-started/installation/install-using-helm/helm-install
# Dependencies: Run:AI Backend (control plane), GPU Operator, Prometheus Stack,
#               Prometheus Adapter, LeaderWorkerSet Operator, Knative Operator, Ingress

# =============================================================================
# Run:AI Cluster Namespace
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
# JFrog Registry Credentials (cluster namespace)
# =============================================================================

resource "kubernetes_secret" "runai_reg_creds_cluster" {
  count = var.enable_runai && var.runai_jfrog_token != "" ? 1 : 0

  metadata {
    name      = "runai-reg-creds"
    namespace = kubernetes_namespace.runai[0].metadata[0].name
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "runai.jfrog.io" = {
          username = var.runai_jfrog_username
          password = var.runai_jfrog_token
          auth     = base64encode("${var.runai_jfrog_username}:${var.runai_jfrog_token}")
        }
      }
    })
  }
}

# =============================================================================
# TLS Certificate for Run:AI
# =============================================================================

resource "tls_private_key" "runai" {
  count = var.enable_runai && var.generate_self_signed_cert ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "runai" {
  count = var.enable_runai && var.generate_self_signed_cert ? 1 : 0

  private_key_pem = tls_private_key.runai[0].private_key_pem

  subject {
    common_name  = var.runai_domain
    organization = "Run:AI Cluster"
  }

  dns_names = [
    var.runai_domain,
    "*.${var.runai_domain}",
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
# Only deploys if client secret is provided (obtained from control plane UI)
# Two-phase deployment:
#   Phase 1: Deploy control plane (runai-backend.tf) → access UI → create cluster
#   Phase 2: Provide client_secret and cluster_uid → deploy this resource
# =============================================================================

resource "helm_release" "runai_cluster" {
  count = var.enable_runai && var.runai_client_secret != "" ? 1 : 0

  name                = "runai-cluster"
  repository          = "https://runai.jfrog.io/artifactory/run-ai-charts"
  # Note: run-ai-charts repo may use same or different credentials than cp-charts-prod
  # If this fails with 403, contact NVIDIA for run-ai-charts repo credentials
  repository_username = var.runai_helm_username != "" ? var.runai_helm_username : var.runai_jfrog_username
  repository_password = var.runai_helm_token != "" ? var.runai_helm_token : var.runai_jfrog_token
  chart               = "runai-cluster"
  version             = var.runai_cluster_version
  namespace           = kubernetes_namespace.runai[0].metadata[0].name
  create_namespace    = false

  wait    = true
  timeout = 900 # 15 minutes

  # ==========================================================================
  # Control Plane Connection (local self-hosted backend)
  # ==========================================================================

  set {
    name  = "controlPlane.url"
    value = "https://${var.runai_domain}"
  }

  set_sensitive {
    name  = "controlPlane.clientSecret"
    value = var.runai_client_secret
  }

  # ==========================================================================
  # Cluster Identification
  # ==========================================================================

  set {
    name  = "cluster.uid"
    value = var.runai_cluster_uid
  }

  set {
    name  = "cluster.url"
    value = "https://${var.runai_domain}"
  }

  # ==========================================================================
  # Custom CA for self-signed certificates
  # ==========================================================================

  set {
    name  = "global.customCA.enabled"
    value = tostring(var.generate_self_signed_cert)
  }

  # ==========================================================================
  # TLS Configuration
  # ==========================================================================

  set {
    name  = "spec.researcherService.ingress.tlsSecret"
    value = kubernetes_secret.runai_tls[0].metadata[0].name
  }

  # ==========================================================================
  # Disable Bundled Components (deployed separately)
  # ==========================================================================

  set {
    name  = "gpu-operator.enabled"
    value = "false"
  }

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
    value = var.runai_domain
  }

  set {
    name  = "ingress.tlsSecretName"
    value = kubernetes_secret.runai_tls[0].metadata[0].name
  }

  # ==========================================================================
  # All dependencies must be ready before Run:AI cluster installation
  # ==========================================================================

  depends_on = [
    kubernetes_namespace.runai,
    kubernetes_secret.runai_tls,
    kubernetes_secret.runai_reg_creds_cluster,
    helm_release.runai_backend,
    helm_release.gpu_operator,
    helm_release.ingress_nginx,
    helm_release.prometheus_stack,
    helm_release.prometheus_adapter,
    helm_release.lws_operator,
    helm_release.knative_operator
  ]
}
