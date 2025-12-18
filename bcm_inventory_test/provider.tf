# BCM Provider Configuration
# Set credentials via environment variables:
#   export BCM_ENDPOINT="https://bcm.example.com:8081"
#   export BCM_USERNAME="automation-user"
#   export BCM_PASSWORD="your-secure-password"

provider "bcm" {
  endpoint             = var.bcm_endpoint
  username             = var.bcm_username
  password             = var.bcm_password
  insecure_skip_verify = var.bcm_insecure_skip_verify
  timeout              = var.bcm_timeout
}
