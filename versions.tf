terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
  }
  required_version = ">=0.13"
}
