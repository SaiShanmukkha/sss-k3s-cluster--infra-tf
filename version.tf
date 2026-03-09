terraform {
  required_version = ">=1.6.0"

  cloud {
    organization = "sss-devops-engineering"          # ← replace with your TF Cloud org name
    workspaces {
      name = "sss-k3s-cluster"
    }
  }

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
  region = var.region
  # No profile — credentials come from TF Cloud workspace env vars (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}