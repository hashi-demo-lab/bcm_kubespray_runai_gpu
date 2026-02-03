# Run:AI Control Plane (Self-Hosted Backend)
# Feature: Run:AI Platform Deployment
# Spec: cm-kubernetes-setup.conf - Run:ai (self-hosted)
# Docs: https://run-ai-docs.nvidia.com/self-hosted/2.21/getting-started/installation/install-using-helm/install-control-plane
# Dependencies: Ingress Controller (Nginx), Prometheus Stack, Prometheus Adapter, GPU Operator

# =============================================================================
# Run:AI Backend Namespace
# =============================================================================

resource "kubernetes_namespace" "runai_backend" {
  count = var.enable_runai ? 1 : 0

  metadata {
    name = "runai-backend"

    labels = {
      "app.kubernetes.io/name"             = "runai-backend"
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

# =============================================================================
# JFrog Registry Credentials
# Required to pull Run:AI images and Helm charts
# =============================================================================

resource "kubernetes_secret" "runai_reg_creds_backend" {
  count = var.enable_runai && var.runai_jfrog_token != "" ? 1 : 0

  metadata {
    name      = "runai-reg-creds"
    namespace = kubernetes_namespace.runai_backend[0].metadata[0].name
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
# Custom CA Certificate Secret
# Required when global.customCA.enabled is true (self-signed certs)
# =============================================================================

resource "kubernetes_secret" "runai_ca_cert" {
  count = var.enable_runai && var.generate_self_signed_cert ? 1 : 0

  metadata {
    name      = "runai-ca-cert"
    namespace = kubernetes_namespace.runai_backend[0].metadata[0].name
  }

  type = "Opaque"

  data = {
    "runai-ca.pem" = tls_self_signed_cert.runai[0].cert_pem
  }

  depends_on = [
    kubernetes_namespace.runai_backend
  ]
}

# =============================================================================
# Run:AI Control Plane Installation via Helm
# Deploys: Keycloak, PostgreSQL, Redis, Thanos, Grafana, Backend services
# =============================================================================

resource "helm_release" "runai_backend" {
  count = var.enable_runai ? 1 : 0

  name       = "runai-backend"
  repository = "https://runai.jfrog.io/artifactory/cp-charts-prod"
  # Note: Helm chart repo is public, no credentials needed
  # Only container image registry (runai.jfrog.io) requires credentials
  chart      = "control-plane"
  version    = var.runai_backend_version
  namespace  = kubernetes_namespace.runai_backend[0].metadata[0].name
  create_namespace = false

  wait    = true
  timeout = 1200 # 20 minutes per BCM config

  # ==========================================================================
  # Global Configuration
  # ==========================================================================

  set {
    name  = "global.domain"
    value = var.runai_domain
  }

  set {
    name  = "global.customCA.enabled"
    value = tostring(var.generate_self_signed_cert)
  }

  # Custom CA secret name - must match kubernetes_secret.runai_ca_cert
  set {
    name  = "global.customCA.secretName"
    value = "runai-ca-cert"
  }

  # ==========================================================================
  # Admin Credentials
  # ==========================================================================

  set {
    name  = "tenantsManager.config.adminUsername"
    value = var.runai_admin_email
  }

  set_sensitive {
    name  = "tenantsManager.config.adminPassword"
    value = var.runai_admin_password
  }

  # ==========================================================================
  # Node Affinity and Tolerations
  # From cm-kubernetes-setup.conf - schedule on control-plane nodes
  # ==========================================================================

  values = [<<-EOT
    global:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 1
              preference:
                matchExpressions:
                  - key: node-role.kubernetes.io/runai-system
                    operator: Exists
    # Backend services - control-plane tolerations
    assetsService:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    auditService:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    authorization:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    backend:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    cliExposer:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    clusterService:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    datavolumes:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    emailService:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    frontend:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    identityManager:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    k8sObjectsTracker:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    metricsService:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    orgUnitService:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    policyService:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    presetsLoader:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    redoc:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    tenantsManager:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    traefik:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    trialService:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    workloads:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    notificationsService:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    # Dependencies - control-plane tolerations
    grafana:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    keycloakx:
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
    postgresql:
      primary:
        tolerations:
          - key: "node-role.kubernetes.io/control-plane"
            operator: "Exists"
            effect: "NoSchedule"
    redisQueue:
      master:
        nodeAffinityPreset:
          type: soft
          key: "node-role.kubernetes.io/runai-system"
          values:
            - "true"
        tolerations:
          - key: "node-role.kubernetes.io/control-plane"
            operator: "Exists"
            effect: "NoSchedule"
    thanos:
      receive:
        tolerations:
          - key: "node-role.kubernetes.io/control-plane"
            operator: "Exists"
            effect: "NoSchedule"
      query:
        tolerations:
          - key: "node-role.kubernetes.io/control-plane"
            operator: "Exists"
            effect: "NoSchedule"
  EOT
  ]

  depends_on = [
    kubernetes_namespace.runai_backend,
    kubernetes_secret.runai_reg_creds_backend,
    kubernetes_secret.runai_ca_cert,
    helm_release.ingress_nginx,
    helm_release.prometheus_stack,
    helm_release.prometheus_adapter,
    helm_release.gpu_operator
  ]
}
