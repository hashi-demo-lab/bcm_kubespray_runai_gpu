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

variable "target_nodes" {
  description = "List of node hostnames to include in inventory"
  type        = list(string)
  default     = ["cpu-03", "cpu-05", "cpu-06"]
}

variable "ansible_user" {
  description = "SSH user for Ansible connections"
  type        = string
  default     = "ansible"
}

variable "ansible_ssh_private_key_file" {
  description = "Path to SSH private key file"
  type        = string
  default     = "~/.ssh/id_rsa"
}
