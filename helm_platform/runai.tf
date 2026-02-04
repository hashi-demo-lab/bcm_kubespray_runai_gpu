# Run:AI Cluster Component (Self-Hosted)
# Feature: Run:AI Platform Deployment
# Spec: cm-kubernetes-setup.conf - Run:ai (SaaS) chart used as cluster component
# Docs: https://run-ai-docs.nvidia.com/self-hosted/2.21/getting-started/installation/install-using-helm/helm-install
# Dependencies: Run:AI Backend (control plane), GPU Operator, Prometheus Stack,
#               Prometheus Adapter, LeaderWorkerSet Operator, Knative Operator, Ingress

# =============================================================================
# Automatic Cluster Creation via API (Phase 2)
# Creates cluster in Run:AI control plane and retrieves credentials
# =============================================================================

data "external" "runai_cluster_credentials" {
  count = var.enable_runai && var.enable_auto_cluster_creation && length(helm_release.runai_backend) > 0 ? 1 : 0

  program = ["bash", "${path.module}/../scripts/create-runai-cluster.sh", var.runai_cluster_name]

  query = {
    # These are passed as environment variables to the script
    dummy = "trigger"
  }

  depends_on = [
    helm_release.runai_backend
  ]
}

locals {
  # Use auto-created credentials if available, otherwise use manually provided ones
  runai_cluster_uid = (
    var.runai_cluster_uid != "" ? var.runai_cluster_uid :
    (length(data.external.runai_cluster_credentials) > 0 ? 
      data.external.runai_cluster_credentials[0].result.cluster_uid : "")
  )
  
  runai_client_secret = (
    var.runai_client_secret != "" ? var.runai_client_secret :
    (length(data.external.runai_cluster_credentials) > 0 ? 
      data.external.runai_cluster_credentials[0].result.client_secret : "")
  )
}

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
# Custom CA Certificate Secret (cluster namespace)
# Required for pre-install job to trust self-signed certs
# =============================================================================

resource "kubernetes_secret" "runai_ca_cert_cluster" {
  count = var.enable_runai && var.generate_self_signed_cert ? 1 : 0

  metadata {
    name      = "runai-ca-cert"
    namespace = kubernetes_namespace.runai[0].metadata[0].name
  }

  type = "Opaque"

  data = {
    # Run:AI pre-install job expects specific key names
    "ca.crt"        = tls_self_signed_cert.runai[0].cert_pem
    "ca-bundle.crt" = tls_self_signed_cert.runai[0].cert_pem
    "runai-ca.pem"  = tls_self_signed_cert.runai[0].cert_pem
  }

  depends_on = [
    kubernetes_namespace.runai
  ]
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
# Pre-Install Job Cleanup
# Removes any failed pre-install/pre-delete jobs before deployment
# =============================================================================

resource "null_resource" "cleanup_runai_jobs" {
  count = var.enable_runai && local.runai_client_secret != "" ? 1 : 0

  triggers = {
    # Re-run cleanup whenever cluster UID or secret changes
    cluster_uid = local.runai_cluster_uid
    always_run  = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl delete job -n runai pre-install pre-delete --ignore-not-found=true || true
    EOT
    environment = {
      KUBECONFIG = "${path.root}/../kubeconfig"
    }
  }

  depends_on = [
    kubernetes_namespace.runai,
    kubernetes_secret.runai_ca_cert_cluster
  ]
}

# =============================================================================
# Run:AI Cluster Installation via Helm
# Deploys automatically when:
#   - enable_auto_cluster_creation = true (uses API to create cluster)
#   - OR runai_client_secret is manually provided
# =============================================================================

resource "helm_release" "runai_cluster" {
  count = var.enable_runai && local.runai_client_secret != "" ? 1 : 0

  name       = "runai-cluster"
  repository = "https://runai.jfrog.io/artifactory/run-ai-charts"
  # Note: Helm chart repos (cp-charts-prod, run-ai-charts) are public
  # Only container image registry (runai.jfrog.io) requires JFrog credentials
  chart      = "runai-cluster"
  version    = var.runai_cluster_version
  namespace  = kubernetes_namespace.runai[0].metadata[0].name
  create_namespace = false

  wait    = true
  timeout = 900 # 15 minutes

  # ==========================================================================
  # Control Plane Connection (local self-hosted backend)
  # ==========================================================================

  set {
    name  = "controlPlane.url"
    value = "https://${var.runai_domain}:${var.runai_external_port}"
  }

  set_sensitive {
    name  = "controlPlane.clientSecret"
    value = local.runai_client_secret
  }

  # ==========================================================================
  # Cluster Identification
  # ==========================================================================

  set {
    name  = "cluster.uid"
    value = local.runai_cluster_uid
  }

  set {
    name  = "cluster.url"
    value = "https://${var.runai_domain}:${var.runai_external_port}"
  }

  # ==========================================================================
  # Custom CA for self-signed certificates
  # Structure from chart values.yaml: global.customCA.secret.name/key
  # ==========================================================================

  values = [
    yamlencode({
      global = {
        customCA = {
          enabled = var.generate_self_signed_cert
          secret = {
            name = "runai-ca-cert"
            key  = "runai-ca.pem"
          }
        }
      }
    })
  ]

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
    null_resource.cleanup_runai_jobs,
    kubernetes_namespace.runai,
    kubernetes_secret.runai_tls,
    kubernetes_secret.runai_reg_creds_cluster,
    kubernetes_secret.runai_ca_cert_cluster,
    helm_release.runai_backend,
    helm_release.gpu_operator,
    helm_release.ingress_nginx,
    helm_release.prometheus_stack,
    helm_release.prometheus_adapter,
    helm_release.lws_operator,
    helm_release.knative_operator
  ]
}
