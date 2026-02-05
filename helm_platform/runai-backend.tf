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
# TLS Secret for Ingress
# Required for HTTPS termination at ingress - referenced as "runai-backend-tls"
# =============================================================================

resource "kubernetes_secret" "runai_backend_tls" {
  count = var.enable_runai && var.generate_self_signed_cert ? 1 : 0

  metadata {
    name      = "runai-backend-tls"
    namespace = kubernetes_namespace.runai_backend[0].metadata[0].name
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = tls_self_signed_cert.runai[0].cert_pem
    "tls.key" = tls_private_key.runai[0].private_key_pem
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
  # Admin Credentials (using set for sensitive values)
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
  # Consolidated Values Configuration
  # Using values block for complex nested structures (customCA, keycloak, etc.)
  # ==========================================================================

  values = [<<-EOT
    global:
      # Domain without port - Ingress hostnames cannot contain ports (RFC 1123)
      domain: "${var.runai_domain}"
      # Keycloak external URL with port for token validation
      # Backend services use this to construct the expected issuer URL
      keycloakExternalEndpoint: "${var.runai_domain}:${var.runai_external_port}"
      # Custom CA for self-signed certificates (control-plane chart structure)
      customCA:
        enabled: ${var.generate_self_signed_cert}
        env:
          - name: NODE_EXTRA_CA_CERTS
            value: /etc/ssl/certs/runai-ca.pem
        volumes:
          - name: runai-ca-cert
            secret:
              secretName: runai-ca-cert
        volumeMounts:
          - mountPath: /etc/ssl/certs/runai-ca.pem
            name: runai-ca-cert
            readOnly: true
            subPath: runai-ca.pem
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 1
              preference:
                matchExpressions:
                  - key: node-role.kubernetes.io/runai-system
                    operator: Exists
    # Keycloak KC_HOSTNAME override - include port for NodePort ingress
    # This sets the OIDC issuer URL to include the NodePort
    # Using extraEnv as YAML string format (codecentric/keycloakx chart format)
    keycloakx:
      extraEnv: |
        - name: KC_HOSTNAME
          value: "https://${var.runai_domain}:${var.runai_external_port}/auth"
        - name: KC_HOSTNAME_STRICT
          value: "false"
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
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
      # Override keycloak external endpoint to include NodePort
      # Without this, backend validates tokens against issuer without port
      keycloakExternalEndpoint: "${var.runai_domain}:${var.runai_external_port}"
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
    # keycloakx is defined earlier with extraEnv - DO NOT duplicate here
    # (tolerations moved to the earlier keycloakx block)
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
    kubernetes_secret.runai_backend_tls,
    helm_release.ingress_nginx,
    helm_release.prometheus_stack,
    helm_release.prometheus_adapter,
    helm_release.gpu_operator
  ]
}
