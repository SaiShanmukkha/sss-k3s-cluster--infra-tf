region       = "ap-south-1"
project_name = "sss-k3s"
environment  = "dev"

# VPC
vpc_cidr = "10.0.0.0/16"

public_subnet_cidrs = {
  "ap-south-1a" = "10.0.1.0/24"
  "ap-south-1b" = "10.0.2.0/24"
  "ap-south-1c" = "10.0.3.0/24"
}

private_subnet_cidrs = {
  "ap-south-1a" = "10.0.11.0/24"
  "ap-south-1b" = "10.0.12.0/24"
  "ap-south-1c" = "10.0.13.0/24"
}

enable_nat_gateway      = true
public_nat_subnet_cidrs = ["ap-south-1a"]

# SSH to bastion is intentionally open to the internet
bastion_allowed_cidr = "0.0.0.0/0"

# K3s - v1.34.4+k3s1
k3s_version = "v1.35.2+k3s1"

# Route53
route53_hosted_zone_id = "Z0531688KC76Y201TZI1"

# S3 bucket names — leave commented to auto-generate from cluster name
# etcd_backup_bucket_name     = null
# velero_backup_bucket_name   = null
# longhorn_backup_bucket_name = null



# ---------------------------------------------------------------------------
# SENSITIVE — NEVER put values here. Use secrets.auto.tfvars (gitignored)
# or TF Cloud workspace sensitive variables instead.
# ---------------------------------------------------------------------------
# k3s_token              = ""   # openssl rand -hex 32
# dockerhub_username     = ""
# dockerhub_token        = ""
# keepalived_auth_pass   = ""   # max 8 chars # openssl rand -base64 6
# haproxy_stats_password = ""
