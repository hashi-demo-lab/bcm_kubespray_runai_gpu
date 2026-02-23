# BCM Provider Configuration for Standalone Testing
#
# This file enables the bcm_node_provisioning module to be tested
# independently without the root module.

# ALL Terraform requests go to the BCM head node API (bcm_endpoint) only.
# The BCM head node distributes work to physical nodes internally.
# Terraform never contacts individual node BMC/IPMI interfaces or the
# out-of-band management network (10.229.10.0/24) directly.
provider "bcm" {
  endpoint             = var.bcm_endpoint
  username             = var.bcm_username
  password             = var.bcm_password
  insecure_skip_verify = var.bcm_insecure_skip_verify
  timeout              = var.bcm_timeout
}
