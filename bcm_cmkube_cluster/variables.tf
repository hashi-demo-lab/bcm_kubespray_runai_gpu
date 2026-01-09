# Cluster Configuration Variables
# Based on cm-kubernetes-setup.conf settings
variable "bcm_endpoint" {
  description = "BCM API endpoint URL"
  type        = string
  default     = "https://casper-bright-view-nvidia.axisapps.io"
}

variable "bcm_username" {
  description = "BCM username for authentication"
  type        = string
  sensitive   = true
  default     = "ibm"
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

variable "cluster_name" {
  description = "Kubernetes cluster name (from kc.name in config)"
  type        = string
  default     = "terraform"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.cluster_name))
    error_message = "Cluster name must contain only alphanumeric characters, hyphens, and underscores."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version (from kc.version in config)"
  type        = string
  default     = "1.32.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "Kubernetes version must be in format 'X.Y' (e.g., '1.32')."
  }
}

variable "cni_plugin" {
  description = "CNI plugin for pod networking (from kc.network_plugin in config)"
  type        = string
  default     = "calico"

  validation {
    condition     = contains(["calico", "flannel", "weave"], var.cni_plugin)
    error_message = "CNI plugin must be one of: calico, flannel, weave."
  }
}

variable "force_bypass_validation" {
  description = "Bypass validation warnings during cluster operations"
  type        = bool
  default     = false
}

variable "prevent_destroy" {
  description = "Prevent accidental destruction of the cluster"
  type        = bool
  default     = true
}

# Network Configuration
variable "pod_network_cidr" {
  description = "Pod network CIDR (from networks.pod in config)"
  type        = string
  default     = "172.29.0.0/16"
}

variable "service_network_cidr" {
  description = "Service network CIDR (from networks.service in config)"
  type        = string
  default     = "10.150.0.0/16"
}

variable "cluster_domain" {
  description = "Kubernetes cluster domain (from kc.domain in config)"
  type        = string
  default     = "cluster.local"
}

variable "external_fqdn" {
  description = "External FQDN for cluster access (from kc.external_fqdn in config)"
  type        = string
  default     = "bcm-head-01.eth.cluster"
}

# Node Configuration
variable "expected_master_count" {
  description = "Expected number of master nodes"
  type        = number
  default     = 3
}

variable "expected_worker_count" {
  description = "Expected number of worker nodes"
  type        = number
  default     = 2
}

variable "expected_etcd_count" {
  description = "Expected number of etcd nodes (recommended 3 for HA)"
  type        = number
  default     = 3
}
