# Prometheus Operator Stack Configuration
# Feature: Run:AI Platform Deployment
# Spec: cm-kubernetes-setup.conf - Prometheus Operator Stack
# Dependency: Required for Run:AI metrics

# =============================================================================
# Prometheus Namespace
# =============================================================================

resource "kubernetes_namespace" "prometheus" {
  count = var.enable_prometheus ? 1 : 0

  metadata {
    name = "prometheus"

    labels = {
      "app.kubernetes.io/name" = "prometheus"
    }
  }
}

# =============================================================================
# Prometheus Operator Stack (kube-prometheus-stack)
# Includes: Prometheus, Alertmanager, Grafana, node-exporter
# =============================================================================

resource "helm_release" "prometheus_stack" {
  count = var.enable_prometheus ? 1 : 0

  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.prometheus_stack_version
  namespace  = kubernetes_namespace.prometheus[0].metadata[0].name

  wait    = true
  timeout = 600 # 10 minutes

  # ==========================================================================
  # Prometheus Configuration
  # ==========================================================================

  # GPU metrics scrape config (from cm-kubernetes-setup.conf)
  values = [<<-EOT
    prometheus:
      prometheusSpec:
        additionalScrapeConfigs:
          # GPU metrics from NVIDIA DCGM Exporter
          # Reference: https://docs.nvidia.com/datacenter/cloud-native/gpu-telemetry/latest/kube-prometheus.html
          - job_name: gpu-metrics
            scrape_interval: 1s
            metrics_path: /metrics
            scheme: http
            kubernetes_sd_configs:
              - role: endpoints
                namespaces:
                  names:
                    - gpu-operator
            relabel_configs:
              - source_labels: [__meta_kubernetes_endpoints_name]
                action: drop
                regex: .*-node-feature-discovery-master
              - source_labels: [__meta_kubernetes_pod_node_name]
                action: replace
                target_label: kubernetes_node
        # Resource limits for production
        resources:
          requests:
            cpu: 200m
            memory: 512Mi
          limits:
            memory: 2Gi
        # Retention period
        retention: 15d
        # Storage configuration
        storageSpec:
          volumeClaimTemplate:
            spec:
              accessModes: ["ReadWriteOnce"]
              resources:
                requests:
                  storage: 50Gi

    # Node exporter configuration
    prometheus-node-exporter:
      prometheus:
        monitor:
          attachMetadata:
            node: true
          relabelings:
            - sourceLabels: [__meta_kubernetes_pod_node_name]
              targetLabel: kubernetes_node
              action: replace

    # Grafana configuration
    grafana:
      enabled: ${var.enable_grafana}
      adminPassword: ${var.grafana_admin_password}
      grafana.ini:
        server:
          root_url: "%(protocol)s://%(domain)s:%(http_port)s/grafana/"
          serve_from_sub_path: true
      sidecar:
        dashboards:
          enabled: true
          label: grafana_dashboard
          labelValue: "1"
          searchNamespace: ALL
      # Tolerations to schedule on control plane
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
        - key: node-role.kubernetes.io/master
          operator: Exists
          effect: NoSchedule

    # Alertmanager configuration
    alertmanager:
      alertmanagerSpec:
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
    kubernetes_namespace.prometheus,
    helm_release.local_path_provisioner
  ]
}

# =============================================================================
# Outputs
# =============================================================================

output "prometheus_namespace" {
  description = "Prometheus namespace"
  value       = var.enable_prometheus ? kubernetes_namespace.prometheus[0].metadata[0].name : null
}

output "prometheus_service_name" {
  description = "Prometheus service name for Run:AI integration"
  value       = var.enable_prometheus ? "kube-prometheus-stack-prometheus" : null
}
