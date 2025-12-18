# Provider Configurations
# Feature: BCM-based Kubernetes Deployment via Kubespray
#
# This configuration uses BCM to discover physical nodes and
# dynamically builds Ansible inventory for Kubespray deployment.

# =============================================================================
# BCM Provider Configuration
# =============================================================================
# Set credentials via environment variables or HCP Terraform workspace variables:
#   BCM_ENDPOINT  - API endpoint URL
#   BCM_USERNAME  - Username for authentication
#   BCM_PASSWORD  - Password for authentication (sensitive)

provider "bcm" {
  endpoint             = var.bcm_endpoint
  username             = var.bcm_username
  password             = var.bcm_password
  insecure_skip_verify = var.bcm_insecure_skip_verify
  timeout              = var.bcm_timeout
}

# =============================================================================
# Ansible Provider Configuration
# =============================================================================
# SSH connectivity handled via resource-level connection blocks

provider "ansible" {
  # No explicit configuration required
  # SSH authentication configured per-resource using var.ssh_private_key
}
