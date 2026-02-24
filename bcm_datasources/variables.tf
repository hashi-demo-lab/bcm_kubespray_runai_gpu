# BCM Provider Variables

variable "bcm_endpoint" {
  description = "BCM API endpoint URL"
  type        = string
}

variable "bcm_username" {
  description = "BCM API username"
  type        = string
}

variable "bcm_password" {
  description = "BCM API password"
  type        = string
  sensitive   = true
}

variable "bcm_insecure_skip_verify" {
  description = "Skip TLS certificate verification"
  type        = bool
  default     = true
}

variable "bcm_timeout" {
  description = "API request timeout in seconds"
  type        = number
  default     = 30
}
