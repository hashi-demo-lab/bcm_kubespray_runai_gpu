# Input Variable Declarations
# Feature: vSphere VM Provisioning with Kubernetes Deployment via Kubespray
# Spec: /workspace/specs/001-vsphere-k8s-kubespray/spec.md
# Data Model: /workspace/specs/001-vsphere-k8s-kubespray/data-model.md
#
# Using private module: tfo-apj-demos/single-virtual-machine/vsphere v1.4.2

# =============================================================================
# vSphere Infrastructure Variables (Module Inputs)
# =============================================================================

variable "vsphere_site" {
  description = "vSphere datacenter/site identifier for VM placement (FR-001). Maps to module 'site' input."
  type        = string

  validation {
    condition     = length(var.vsphere_site) > 0
    error_message = "vSphere site must be specified."
  }
}

variable "vsphere_folder" {
  description = "vSphere folder path for VM organization (FR-001). Maps to module 'folder_path' input."
  type        = string
  default     = "Demo Workloads"
}

variable "environment" {
  description = "Deployment environment classification (dev, staging, prod) (FR-002)"
  type        = string

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
  default     = "vsphere-k8s-cluster"

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

# =============================================================================
# SSH Configuration Variables
# =============================================================================

variable "ssh_user" {
  description = "SSH username for VM access and Ansible connectivity (FR-013)"
  type        = string
  default     = "ubuntu"
}

variable "ssh_private_key" {
  description = "SSH private key content for VM authentication (per SEC-002, stored in HCP Terraform) (FR-013)"
  type        = string
  sensitive   = true
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key file for Ansible playbook execution"
  type        = string
  default     = "~/.ssh/id_rsa"
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
  description = "Kubespray release version or Git tag (FR-011). v2.24.0 supports K8s 1.28.x and requires Python 3.9+"
  type        = string
  default     = "v2.24.0"
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
