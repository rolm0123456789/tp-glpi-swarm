terraform {
  required_providers {
    virtualbox = {
      source = "terra-farm/virtualbox"
      version = "0.2.2-alpha.1"
    }
    local = {
      source = "hashicorp/local"
    }
  }
  required_version = ">= 0.13"
}