# Terraform and Provider Version Constraints
# Feature: BCM-based Kubernetes Deployment via Kubespray
#
# This configuration uses BCM (Base Command Manager) to discover nodes
# and dynamically build Ansible inventory for Kubespray deployment.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    bcm = {
      source  = "hashi-demo-lab/bcm"
      version = "~> 0.1"
    }

    ansible = {
      source  = "ansible/ansible"
      version = "~> 1.3"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}
