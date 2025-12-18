terraform {
  required_version = ">= 1.5.0"

  required_providers {
    bcm = {
      source  = "hashi-demo-lab/bcm"
      version = "~> 0.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
