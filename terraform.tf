# Terraform and Provider Version Constraints
# Feature: vSphere VM Provisioning with Kubernetes Deployment via Kubespray
# Spec: /workspace/specs/001-vsphere-k8s-kubespray/spec.md
# Plan: /workspace/specs/001-vsphere-k8s-kubespray/plan.md
#
# Using private module: tfo-apj-demos/single-virtual-machine/vsphere v1.4.2

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    # vsphere provider is managed by the private module
    # Module version 1.4.2 uses vmware/vsphere ~> 2

    ansible = {
      source  = "ansible/ansible"
      version = "~> 1.3.0"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.4.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.0"
    }

    external = {
      source  = "hashicorp/external"
      version = "~> 2.3.0"
    }
  }
}
