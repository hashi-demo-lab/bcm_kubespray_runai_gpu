# Input Variable Declarations
# Feature: BCM-based Kubernetes Deployment via Kubespray
#
# This configuration uses BCM to discover physical nodes and
# dynamically builds Ansible inventory for Kubespray deployment.

# =============================================================================
# BCM Provider Configuration Variables
# =============================================================================

variable "bcm_endpoint" {
  description = "BCM API endpoint URL"
  type        = string
  default     = null
}

variable "bcm_username" {
  description = "BCM username for authentication"
  type        = string
  sensitive   = true
  default     = null
}

variable "bcm_password" {
  description = "BCM password for authentication"
  type        = string
  sensitive   = true
  default     = null
}

variable "bcm_insecure_skip_verify" {
  description = "Skip TLS certificate verification (only for self-signed certs)"
  type        = bool
  default     = true
}

variable "bcm_timeout" {
  description = "API timeout in seconds"
  type        = number
  default     = 30
}

# =============================================================================
# BCM Node Selection Variables
# =============================================================================

variable "control_plane_nodes" {
  description = "List of BCM node hostnames to use as Kubernetes control plane nodes"
  type        = list(string)
  default     = ["cpu-03", "cpu-05", "cpu-06"]

  validation {
    condition     = length(var.control_plane_nodes) > 0 || length(var.worker_nodes) == 0
    error_message = "At least one control plane node must be specified when worker nodes are defined."
  }
}

variable "worker_nodes" {
  description = "List of BCM node hostnames to use as Kubernetes worker nodes"
  type        = list(string)
  default     = ["dgx-05", "dgx-06"]
}

variable "etcd_nodes" {
  description = "List of BCM node hostnames to use as etcd nodes. Defaults to control plane nodes if not specified."
  type        = list(string)
  default     = []
}

variable "node_production_ips" {
  description = "Map of node hostnames to production network IPs (10.184.162.x). BCM returns out-of-band management IPs (10.229.10.x) which should not be used for deployment."
  type        = map(string)
  default = {
    "cpu-03" = "10.184.162.102"
    "cpu-05" = "10.184.162.104"
    "cpu-06" = "10.184.162.121"
    "dgx-05" = "10.184.162.109"
    "dgx-06" = "10.184.162.110"
  }
}

# =============================================================================
# BCM Infrastructure Variables (Module Inputs)
# =============================================================================
# These variables support BCM-managed bare metal node deployments.
# Legacy vSphere variables have been removed.

variable "environment" {
  description = "Deployment environment classification (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

# =============================================================================
# VM Configuration Variables (Module Inputs)
# =============================================================================

variable "control_plane_vm_size" {
  description = "VM size tier for control plane node (must meet minimum 2 CPU, 4GB RAM per FR-005). Maps to module 'size' input."
  type        = string
  default     = "medium"

  validation {
    condition     = contains(["medium", "large", "xlarge"], var.control_plane_vm_size)
    error_message = "Control plane VM size must be medium or larger to meet Kubernetes requirements."
  }
}

variable "worker_vm_size" {
  description = "VM size tier for worker nodes (must meet minimum 2 CPU, 4GB RAM per FR-005). Maps to module 'size' input."
  type        = string
  default     = "medium"

  validation {
    condition     = contains(["medium", "large", "xlarge"], var.worker_vm_size)
    error_message = "Worker VM size must be medium or larger to meet Kubernetes requirements."
  }
}

variable "storage_profile" {
  description = "Storage performance profile for VM disks (FR-006). Maps to module 'storage_profile' input."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "performance", "premium"], var.storage_profile)
    error_message = "Storage profile must be standard, performance, or premium."
  }
}

variable "service_tier" {
  description = "Service tier classification for resource allocation. Maps to module 'tier' input."
  type        = string
  default     = "gold"

  validation {
    condition     = contains(["bronze", "silver", "gold", "platinum"], var.service_tier)
    error_message = "Service tier must be bronze, silver, gold, or platinum."
  }
}

variable "backup_policy" {
  description = "Backup policy for VM data protection. Maps to module 'backup_policy' input."
  type        = string
  default     = "daily"

  validation {
    condition     = contains(["none", "daily", "weekly"], var.backup_policy)
    error_message = "Backup policy must be none, daily, or weekly."
  }
}

variable "security_profile" {
  description = "Security profile classification for VM hardening (per SEC-007). Maps to module 'security_profile' input."
  type        = string
  default     = "web-server"
}

variable "vm_domain" {
  description = "DNS domain for VMs. Maps to module 'ad_domain' input."
  type        = string
  default     = "local"
}

# =============================================================================
# Kubernetes Configuration Variables
# =============================================================================

variable "cluster_name" {
  description = "Kubernetes cluster name identifier (FR-007)"
  type        = string
  default     = "bcm-k8s-cluster"

  validation {
    condition     = length(var.cluster_name) > 0 && length(var.cluster_name) <= 63
    error_message = "Cluster name must be 1-63 characters."
  }
}

variable "kubernetes_version" {
  description = "Target Kubernetes version for deployment. Must match Kubespray version compatibility - v2.24.0 supports up to v1.28.x (FR-009)"
  type        = string
  default     = "v1.28.6"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "Kubernetes version must be in format vX.Y.Z."
  }
}

variable "cni_plugin" {
  description = "Container Network Interface plugin for pod networking (per FR-010)"
  type        = string
  default     = "calico"

  validation {
    condition     = contains(["calico", "flannel", "cilium"], var.cni_plugin)
    error_message = "CNI plugin must be calico, flannel, or cilium."
  }
}

variable "pod_network_cidr" {
  description = "CIDR for Kubernetes pod network (from cm-kubernetes-setup.conf networks.pod)"
  type        = string
  default     = "172.29.0.0/16"

  validation {
    condition     = can(cidrhost(var.pod_network_cidr, 0))
    error_message = "Pod network CIDR must be a valid CIDR notation."
  }
}

variable "service_network_cidr" {
  description = "CIDR for Kubernetes service network (from cm-kubernetes-setup.conf networks.service)"
  type        = string
  default     = "10.150.0.0/16"

  validation {
    condition     = can(cidrhost(var.service_network_cidr, 0))
    error_message = "Service network CIDR must be a valid CIDR notation."
  }
}

# =============================================================================
# Container Registry Configuration
# =============================================================================

variable "containerd_registry_mirrors" {
  description = "Map of container registries to their mirror endpoints. Used to avoid Docker Hub rate limits."
  type        = map(list(string))
  default = {
    "docker.io" = ["https://mirror.gcr.io", "https://registry-1.docker.io"]
  }
}

variable "docker_hub_username" {
  description = "Docker Hub username for authenticated pulls (optional, increases rate limit)"
  type        = string
  default     = null
  sensitive   = true
}

variable "docker_hub_password" {
  description = "Docker Hub password or access token for authenticated pulls (optional)"
  type        = string
  default     = null
  sensitive   = true
}

# =============================================================================
# SSH Configuration Variables
# =============================================================================

variable "ssh_user" {
  description = "SSH username for VM access and Ansible connectivity (FR-013)"
  type        = string
  default     = "ansiblebcm"
}

variable "ssh_private_key" {
  description = "SSH private key content for VM authentication. If not provided, uses the auto-generated key from tls_private_key.ssh_key"
  type        = string
  sensitive   = true
  default     = null
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key file for Ansible playbook execution. If not provided, uses the auto-generated key file."
  type        = string
  default     = null
}

# =============================================================================
# Admin SSH Configuration Variables (for user existence check and creation)
# =============================================================================

variable "admin_ssh_user" {
  description = "Admin SSH username for checking if user exists and creating the service account if needed. Typically 'root' or a user with passwordless sudo."
  type        = string
  default     = "root"
}

variable "admin_ssh_private_key_path" {
  description = "Path to admin SSH private key file for checking and creating the user. Terraform will automatically check if the user exists on all nodes and only create it if needed. Defaults to ~/.ssh/id_rsa if not specified."
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "skip_user_creation" {
  description = "Skip automatic user existence check and creation. Set to true to bypass all user management (useful if you manage users outside of Terraform)."
  type        = bool
  default     = false
}

# =============================================================================
# Kubespray Configuration Variables
# =============================================================================

variable "kubespray_playbook_path" {
  description = "Path to Kubespray cluster.yml playbook file (FR-011)"
  type        = string
  default     = "./kubespray/cluster.yml"

  validation {
    condition     = can(regex("\\.yml$", var.kubespray_playbook_path))
    error_message = "Kubespray playbook path must reference a .yml file."
  }
}

variable "kubespray_version" {
  description = <<-EOT
    Kubespray release version or Git tag (FR-011).
    
    Version compatibility matrix:
    - v2.24.0: K8s 1.27.x-1.28.x, Python 3.9+
    - v2.25.0: K8s 1.28.x-1.29.x, Python 3.10+
    - v2.26.0: K8s 1.29.x-1.30.x, Python 3.10+
    - v2.27.0+: K8s 1.30.x-1.32.x, Python 3.11+
    
    Update kubernetes_version accordingly when changing this.
  EOT
  type        = string
  default     = "v2.24.0"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubespray_version))
    error_message = "Kubespray version must be in format vX.Y.Z (e.g., v2.24.0)."
  }
}

# =============================================================================
# Ansible Execution Control
# =============================================================================

variable "enable_ansible" {
  description = "Enable SSH connectivity validation to VMs. Set to true to verify VMs are accessible."
  type        = bool
  default     = true
}

variable "enable_ansible_playbook" {
  description = "Enable Ansible playbook execution for Kubespray deployment. Requires ansible-playbook on execution agent. Set to false when using HCP Terraform agents without Ansible installed."
  type        = bool
  default     = true
}

variable "enable_kubespray_deployment" {
  description = "Enable Kubespray deployment via remote provisioner on control plane VM. This installs Ansible on the control plane and runs Kubespray from there."
  type        = bool
  default     = true
}

variable "ansible_version" {
  description = "Ansible version to install on control plane for Kubespray execution."
  type        = string
  default     = "8.7.0"
}

# =============================================================================
# Node User Configuration Variables
# =============================================================================

variable "node_username" {
  description = "Username for the account to create on BCM nodes"
  type        = string
  default     = "ansiblebcm"
}

variable "node_password" {
  description = "Password for the user account (hashed or plaintext depending on BCM configuration)"
  type        = string
  sensitive   = true
  default     = null
}

variable "node_user_full_name" {
  description = "Full name for the user account"
  type        = string
  default     = "Ansible Service Account"
}

variable "node_user_uid" {
  description = "UID for the user account (should match LDAP UID)"
  type        = number
  default     = 60000
}

variable "node_user_gid" {
  description = "GID for the user's primary group (should match LDAP GID)"
  type        = number
  default     = 60000
}

variable "node_user_home_dir" {
  description = "Home directory path for the user. Defaults to /home/<username>"
  type        = string
  default     = null
}

variable "node_user_shell" {
  description = "Login shell for the user account"
  type        = string
  default     = "/bin/bash"
}

variable "node_user_ssh_public_keys" {
  description = "List of SSH public keys to add to the user's authorized_keys file"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for key in var.node_user_ssh_public_keys :
      can(regex("^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)\\s+[A-Za-z0-9+/=]+", key))
    ])
    error_message = "Each SSH public key must be in a valid OpenSSH format (ssh-rsa, ssh-ed25519, or ecdsa-*)."
  }
}
