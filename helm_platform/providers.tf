# Provider Configurations
# Feature: Run:AI Platform Deployment
# Spec: /workspace/specs/002-runai-deployment/plan.md

# =============================================================================
# Kubernetes Provider
# Uses kubeconfig file for authentication (simpler and more reliable)
# =============================================================================

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

# =============================================================================
# Helm Provider
# Uses same kubeconfig as Kubernetes provider
# =============================================================================

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

