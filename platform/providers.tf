# Provider Configurations
# Feature: Run:AI Platform Deployment
# Spec: /workspace/specs/002-runai-deployment/plan.md

# =============================================================================
# Kubernetes Provider
# Uses credentials from infrastructure remote state
# =============================================================================

provider "kubernetes" {
  host                   = local.kubernetes_host
  cluster_ca_certificate = local.kubernetes_ca_certificate
  client_certificate     = local.kubernetes_client_cert
  client_key             = local.kubernetes_client_key
}

# =============================================================================
# Helm Provider
# Uses same credentials as Kubernetes provider
# =============================================================================

provider "helm" {
  kubernetes {
    host                   = local.kubernetes_host
    cluster_ca_certificate = local.kubernetes_ca_certificate
    client_certificate     = local.kubernetes_client_cert
    client_key             = local.kubernetes_client_key
  }
}
