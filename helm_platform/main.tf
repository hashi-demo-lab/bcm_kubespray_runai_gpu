# Local Values for Kubernetes Connection
# Feature: Run:AI Platform Deployment
# Spec: /workspace/specs/002-runai-deployment/plan.md

# =============================================================================
# Local Values from Variables
# =============================================================================

locals {
  # Cluster connection details from variables
  kubernetes_host           = var.kubernetes_host
  kubernetes_ca_certificate = base64decode(var.kubernetes_ca_certificate)
  kubernetes_client_cert    = base64decode(var.kubernetes_client_certificate)
  kubernetes_client_key     = base64decode(var.kubernetes_client_key)

  # Cluster metadata
  cluster_name     = var.cluster_name
  control_plane_ip = var.control_plane_ip
  worker_ips       = var.worker_ips
}
