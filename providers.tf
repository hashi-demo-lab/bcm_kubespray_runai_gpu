# Provider Configurations
# Feature: vSphere VM Provisioning with Kubernetes Deployment via Kubespray
# Spec: /workspace/specs/001-vsphere-k8s-kubespray/spec.md
#
# Using private module: tfo-apj-demos/single-virtual-machine/vsphere v1.4.2

# NOTE: The vsphere provider is managed by the private module.
# vSphere credentials are configured via HCP Terraform workspace variables:
# - VSPHERE_USER
# - VSPHERE_PASSWORD
# - VSPHERE_SERVER

# Ansible provider for Kubespray execution
# SSH connectivity handled via resource-level connection blocks
provider "ansible" {
  # No explicit configuration required
  # SSH authentication configured per-resource using var.ssh_private_key
}
