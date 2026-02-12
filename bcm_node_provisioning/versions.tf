terraform {
  required_version = ">= 1.14.0"

  required_providers {
    bcm = {
      source  = "hashi-demo-lab/bcm"
      version = "~> 0.1"
    }
  }
}
