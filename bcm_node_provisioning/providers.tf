# BCM Provider Configuration for Standalone Testing
#
# This file enables the bcm_node_provisioning module to be tested
# independently without the root module.

provider "bcm" {
  endpoint             = var.bcm_endpoint
  username             = var.bcm_username
  password             = var.bcm_password
  insecure_skip_verify = var.bcm_insecure_skip_verify
  timeout              = var.bcm_timeout
}
