# SSH Key Generation for Node Access
# Feature: BCM-based Kubernetes Deployment via Kubespray
#
# Generates an SSH key pair for Ansible to connect to BCM nodes

# =============================================================================
# Generate SSH Key Pair
# =============================================================================

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# =============================================================================
# Save Private Key to Local File (for Ansible)
# =============================================================================

resource "local_sensitive_file" "ssh_private_key" {
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = "${path.module}/generated_ssh_key"
  file_permission = "0600"
}

# =============================================================================
# Outputs for SSH Key
# =============================================================================

output "ssh_public_key" {
  description = "Generated SSH public key (add to VM template or cloud-init)"
  value       = tls_private_key.ssh_key.public_key_openssh
  sensitive   = false
}

output "ssh_private_key_file" {
  description = "Path to generated SSH private key file"
  value       = local_sensitive_file.ssh_private_key.filename
}
