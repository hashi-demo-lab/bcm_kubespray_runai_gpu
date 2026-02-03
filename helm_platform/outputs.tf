# Output Value Declarations
# Feature: Run:AI Platform Deployment
# Spec: /workspace/specs/002-runai-deployment/plan.md

# =============================================================================
# Cluster Information (from Remote State)
# =============================================================================

output "cluster_name" {
  description = "Kubernetes cluster name"
  value       = local.cluster_name
}

output "kubernetes_api_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = local.kubernetes_host
}

output "control_plane_ip" {
  description = "Control plane node IP address"
  value       = local.control_plane_ip
}

# =============================================================================
# Run:AI Outputs
# =============================================================================

output "runai_enabled" {
  description = "Whether Run:AI is enabled"
  value       = var.enable_runai
}

output "runai_domain" {
  description = "Run:AI domain FQDN"
  value       = var.enable_runai ? var.runai_domain : null
}

output "runai_control_plane_url" {
  description = "Run:AI self-hosted control plane URL"
  value       = var.enable_runai ? "https://${var.runai_domain}" : null
}

output "runai_backend_namespace" {
  description = "Kubernetes namespace for Run:AI control plane"
  value       = var.enable_runai ? kubernetes_namespace.runai_backend[0].metadata[0].name : null
}

output "runai_backend_deployed" {
  description = "Whether Run:AI control plane was deployed (requires JFrog token)"
  value       = var.enable_runai ? length(helm_release.runai_backend) > 0 : false
}

output "runai_namespace" {
  description = "Kubernetes namespace for Run:AI"
  value       = var.enable_runai ? kubernetes_namespace.runai[0].metadata[0].name : null
}

output "runai_cluster_deployed" {
  description = "Whether Run:AI cluster component was deployed (requires client secret from control plane UI)"
  value       = var.enable_runai ? length(helm_release.runai_cluster) > 0 : false
}

# =============================================================================
# GPU Operator Outputs
# =============================================================================

output "gpu_operator_enabled" {
  description = "Whether GPU Operator is enabled"
  value       = var.enable_gpu_operator
}

output "gpu_operator_version" {
  description = "Deployed GPU Operator version"
  value       = var.enable_gpu_operator ? var.gpu_operator_version : null
}

output "gpu_operator_namespace" {
  description = "Kubernetes namespace for GPU Operator"
  value       = var.enable_gpu_operator ? kubernetes_namespace.gpu_operator[0].metadata[0].name : null
}

# =============================================================================
# Supporting Components Outputs
# =============================================================================

output "ingress_nginx_enabled" {
  description = "Whether NGINX Ingress is enabled"
  value       = var.enable_ingress_nginx
}

output "ingress_nginx_http_port" {
  description = "NGINX Ingress HTTP NodePort"
  value       = var.enable_ingress_nginx ? "30080" : null
}

output "ingress_nginx_https_port" {
  description = "NGINX Ingress HTTPS NodePort"
  value       = var.enable_ingress_nginx ? "30443" : null
}

output "local_storage_enabled" {
  description = "Whether local-path-provisioner is enabled"
  value       = var.enable_local_storage
}

# =============================================================================
# Access Information
# =============================================================================

output "runai_access_url" {
  description = "URL to access Run:AI (via NodePort)"
  value       = var.enable_runai ? "https://${local.control_plane_ip}:30443" : null
}
