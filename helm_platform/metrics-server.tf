# Kubernetes Metrics Server Configuration
# Feature: Run:AI Platform Deployment
# Spec: cm-kubernetes-setup.conf - Kubernetes Metrics Server
# Provides resource metrics (CPU/memory) for kubectl top and HPA

# =============================================================================
# Metrics Server
# =============================================================================

resource "helm_release" "metrics_server" {
  count = var.enable_metrics_server ? 1 : 0

  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = var.metrics_server_version
  namespace  = "kube-system"

  wait    = true
  timeout = 300 # 5 minutes

  # ==========================================================================
  # Replica Configuration
  # ==========================================================================

  set {
    name  = "replicas"
    value = "2"
  }

  # ==========================================================================
  # Container Port
  # ==========================================================================

  set {
    name  = "containerPort"
    value = "4443"
  }

  # ==========================================================================
  # Default Arguments (from cm-kubernetes-setup.conf)
  # ==========================================================================

  values = [<<-EOT
    defaultArgs:
      - --cert-dir=/tmp
      - --kubelet-preferred-address-types=InternalIP,Hostname,ExternalIP
      - --kubelet-use-node-status-port
      - --kubelet-insecure-tls
      - --metric-resolution=15s

    # Tolerations to schedule on control plane nodes
    tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule

    # Resource requests
    resources:
      requests:
        cpu: 100m
        memory: 200Mi
  EOT
  ]
}
