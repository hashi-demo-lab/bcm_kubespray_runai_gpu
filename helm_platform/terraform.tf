# Terraform and Provider Version Constraints
# Feature: Run:AI Platform Deployment
# Spec: /workspace/specs/002-runai-deployment/plan.md

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.0"
    }
  }
}
