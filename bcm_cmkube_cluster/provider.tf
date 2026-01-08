provider "bcm" {
  endpoint             = var.bcm_endpoint
  username             = var.bcm_username
  password             = var.bcm_password
  insecure_skip_verify = var.bcm_insecure_skip_verify
  timeout              = var.bcm_timeout
}
