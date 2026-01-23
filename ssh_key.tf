# SSH Key Generation for Node Access
# Feature: BCM-based Kubernetes Deployment via Kubespray
#
# Generates an SSH key pair for Ansible to connect to BCM nodes.
#
# BOOT IMAGE SETUP:
# The ansiblebcm user and this SSH public key should be pre-configured
# in the BCM boot image. Add the following to the boot image setup:
#
#   # Create user
#   groupadd -g 60000 ansiblebcm
#   useradd -m -u 60000 -g 60000 -s /bin/bash ansiblebcm
#
#   # Configure passwordless sudo
#   echo "ansiblebcm ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ansiblebcm
#   chmod 440 /etc/sudoers.d/ansiblebcm
#
#   # Add SSH public key (from terraform output ssh_public_key)
#   mkdir -p /home/ansiblebcm/.ssh
#   echo "<SSH_PUBLIC_KEY>" > /home/ansiblebcm/.ssh/authorized_keys
#   chmod 700 /home/ansiblebcm/.ssh
#   chmod 600 /home/ansiblebcm/.ssh/authorized_keys
#   chown -R ansiblebcm:ansiblebcm /home/ansiblebcm/.ssh

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
# Save Public Key to Local File (for boot image setup)
# =============================================================================

resource "local_file" "ssh_public_key" {
  content         = tls_private_key.ssh_key.public_key_openssh
  filename        = "${path.module}/generated_ssh_key.pub"
  file_permission = "0644"
}

# =============================================================================
# Outputs for SSH Key
# =============================================================================

output "ssh_public_key" {
  description = "Generated SSH public key - ADD THIS TO BOOT IMAGE for ansiblebcm user"
  value       = trimspace(tls_private_key.ssh_key.public_key_openssh)
  sensitive   = false
}

output "ssh_private_key_file" {
  description = "Path to generated SSH private key file"
  value       = local_sensitive_file.ssh_private_key.filename
}

output "ssh_public_key_file" {
  description = "Path to generated SSH public key file (copy to boot image)"
  value       = local_file.ssh_public_key.filename
}
