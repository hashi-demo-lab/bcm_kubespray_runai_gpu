# Input Variable Declarations
# Feature: Run:AI Platform Deployment
# Spec: /workspace/specs/002-runai-deployment/plan.md

# =============================================================================
# Kubernetes Cluster Connection Configuration
# =============================================================================

variable "kubernetes_host" {
  description = "Kubernetes API server endpoint URL"
  type        = string
}

variable "kubernetes_ca_certificate" {
  description = "Base64-encoded Kubernetes cluster CA certificate"
  type        = string
  sensitive   = true
}

variable "kubernetes_client_certificate" {
  description = "Base64-encoded Kubernetes client certificate"
  type        = string
  sensitive   = true
}

variable "kubernetes_client_key" {
  description = "Base64-encoded Kubernetes client private key"
  type        = string
  sensitive   = true
}

# =============================================================================
# Cluster Metadata
# =============================================================================

variable "cluster_name" {
  description = "Kubernetes cluster name"
  type        = string
  default     = "bcm-k8s-cluster"
}

variable "control_plane_ip" {
  description = "IP address of the Kubernetes control plane"
  type        = string
  default     = null
}

variable "worker_ips" {
  description = "List of worker node IP addresses"
  type        = list(string)
  default     = []
}

# =============================================================================
# Run:AI Configuration
# =============================================================================

variable "enable_runai" {
  description = "Enable Run:AI deployment on the Kubernetes cluster"
  type        = bool
  default     = true
}

variable "runai_version" {
  description = "Run:AI Helm chart version"
  type        = string
  default     = "2.19.0"
}

variable "runai_cluster_name" {
  description = "Run:AI cluster name for registration in console"
  type        = string
  default     = "vsphere-k8s-cluster"
}

variable "runai_cluster_url" {
  description = "FQDN for Run:AI cluster access (e.g., runai.example.com)"
  type        = string
  default     = "runai.hashicorp.local"
}

variable "runai_control_plane_url" {
  description = "Run:AI control plane URL (SaaS: https://app.run.ai)"
  type        = string
  default     = "https://app.run.ai"
}

variable "runai_cluster_token" {
  description = "Run:AI cluster authentication token (from Run:AI console)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "runai_cluster_uid" {
  description = "Run:AI cluster UID (from Run:AI console)"
  type        = string
  default     = ""
}

# =============================================================================
# NVIDIA GPU Operator Configuration
# =============================================================================

variable "enable_gpu_operator" {
  description = "Enable NVIDIA GPU Operator deployment"
  type        = bool
  default     = true
}

variable "gpu_operator_version" {
  description = "NVIDIA GPU Operator Helm chart version"
  type        = string
  default     = "v24.6.0"
}

variable "gpu_driver_enabled" {
  description = "Deploy GPU drivers as containers (set false if pre-installed on nodes)"
  type        = bool
  default     = true
}

variable "gpu_driver_version" {
  description = "NVIDIA driver version to install"
  type        = string
  default     = "550.54.15"
}

# =============================================================================
# Supporting Components Configuration
# =============================================================================

variable "enable_ingress_nginx" {
  description = "Enable NGINX Ingress Controller deployment"
  type        = bool
  default     = true
}

variable "ingress_nginx_version" {
  description = "NGINX Ingress Controller Helm chart version"
  type        = string
  default     = "4.9.0"
}


variable "enable_local_storage" {
  description = "Enable local-path-provisioner for default StorageClass"
  type        = bool
  default     = true
}

variable "local_storage_version" {
  description = "local-path-provisioner Helm chart version"
  type        = string
  default     = "0.0.26"
}

# =============================================================================
# TLS Configuration
# =============================================================================

variable "generate_self_signed_cert" {
  description = "Generate self-signed TLS certificate for Run:AI"
  type        = bool
  default     = true
}

variable "runai_tls_cert" {
  description = "TLS certificate for Run:AI cluster (PEM format). Required if generate_self_signed_cert is false."
  type        = string
  sensitive   = true
  default     = ""
}

variable "runai_tls_key" {
  description = "TLS private key for Run:AI cluster (PEM format). Required if generate_self_signed_cert is false."
  type        = string
  sensitive   = true
  default     = ""
}
