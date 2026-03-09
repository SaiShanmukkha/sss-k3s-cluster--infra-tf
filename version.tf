terraform {
  required_version = ">=1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }

    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }

  }
}


provider "aws" {
  region  = var.region
  profile = "tf-optimus-user"
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}