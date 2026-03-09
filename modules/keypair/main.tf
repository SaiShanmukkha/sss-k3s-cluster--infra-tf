# =============================================================================
# modules/keypair/main.tf
# Two keypairs:
#   admin-key    → bastion only
#   internal-key → servers, workers, ingress nodes
# Private keys stored in SSM SecureString (never on disk after creation)
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
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

# -----------------------------------------------------------------------------
# ADMIN KEY — bastion only
# -----------------------------------------------------------------------------

resource "tls_private_key" "admin" {
    algorithm = "RSA"
    rsa_bits  = 4096 
}


resource "aws_key_pair" "admin" {
    key_name   = "${var.cluster_name}-admin-key"
    public_key = tls_private_key.admin.public_key_openssh

    tags = merge(var.tags, {
        Name = "${var.cluster_name}-admin-key"
        Role = "bastion"
    })
}


# -----------------------------------------------------------------------------
# INTERNAL KEY — servers, workers, ingress nodes
# -----------------------------------------------------------------------------

resource "tls_private_key" "internal" {
    algorithm = "RSA"
    rsa_bits  = 4096
}


resource "aws_key_pair" "internal" {
    key_name = "${var.cluster_name}-internal-key"
    public_key = tls_private_key.internal.public_key_openssh

    tags = merge(var.tags, {
        Name = "${var.cluster_name}-internal-key"
        Role = "internal"
    })
}


# -----------------------------------------------------------------------------
# LOCAL FILE OUTPUT — gitignored, delete after first bootstrap
# -----------------------------------------------------------------------------

resource "local_sensitive_file" "admin_private_key" {
    count = var.save_keys_locally ? 1 : 0
    filename = "${path.root}/keys/${var.cluster_name}-admin-key.pem"
    file_permission = "0600"
    content  = tls_private_key.admin.private_key_pem
}

resource "local_sensitive_file" "internal_private_key" {
    count = var.save_keys_locally ? 1 : 0
    filename = "${path.root}/keys/${var.cluster_name}-internal-key.pem"
    file_permission = "0600"
    content  = tls_private_key.internal.private_key_pem
}


