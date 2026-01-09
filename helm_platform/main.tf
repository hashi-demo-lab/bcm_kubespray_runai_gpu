# Terraform Cloud Outputs and Local Values
# Feature: Run:AI Platform Deployment
# Spec: /workspace/specs/002-runai-deployment/plan.md

# =============================================================================
# Terraform Cloud Outputs from Infrastructure Workspace
# Reads kubeconfig and cluster details for provider configuration
# =============================================================================

data "tfe_outputs" "infrastructure" {
  organization = var.tfc_organization
  workspace    = var.infrastructure_workspace
}

# =============================================================================
# Local Values from TFC Outputs
# =============================================================================

locals {
  # Cluster connection details from infrastructure outputs
  kubernetes_host           = data.tfe_outputs.infrastructure.values.kubernetes_api_endpoint
  kubernetes_ca_certificate = base64decode(data.tfe_outputs.infrastructure.values.kubeconfig_ca_certificate)
  kubernetes_client_cert    = base64decode(data.tfe_outputs.infrastructure.values.kubeconfig_client_certificate)
  kubernetes_client_key     = base64decode(data.tfe_outputs.infrastructure.values.kubeconfig_client_key)

  # Cluster metadata
  cluster_name     = data.tfe_outputs.infrastructure.values.cluster_name
  control_plane_ip = data.tfe_outputs.infrastructure.values.control_plane_ip
  worker_ips       = data.tfe_outputs.infrastructure.values.worker_ips
}
