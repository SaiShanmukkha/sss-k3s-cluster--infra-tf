/* Root module Variables */
variable "region" {
  default     = "ap-south-1"
  type        = string
  description = "AWS Cloud Region"
  nullable    = false
  sensitive   = false
  ephemeral   = false
}

variable "project_name" {
  default     = "sss-k3s"
  type        = string
  description = "Project Name"
  nullable    = false
  sensitive   = false
  ephemeral   = false
}

variable "environment" {
  default     = "dev"
  type        = string
  description = "Environment Name"
  nullable    = false
  sensitive   = false
  ephemeral   = false
}

/* VPC Module Variables */
variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  nullable    = false
  sensitive   = false
  ephemeral   = false
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = map(string)
  description = "List of CIDR blocks for public subnets"
  nullable    = false
  sensitive   = false
  ephemeral   = false
  default = {
    "ap-south-1a" = "10.0.1.0/24"
    "ap-south-1b" = "10.0.2.0/24"
    "ap-south-1c" = "10.0.3.0/24"
  }
}

variable "private_subnet_cidrs" {
  type        = map(string)
  description = "List of CIDR blocks for private subnets."
  nullable    = false
  sensitive   = false
  ephemeral   = false
  default = {
    "ap-south-1a" = "10.0.11.0/24"
    "ap-south-1b" = "10.0.12.0/24"
    "ap-south-1c" = "10.0.13.0/24"
  }
}

variable "public_nat_subnet_cidrs" {
  default = ["ap-south-1a"]

  type        = set(string)
  description = "Set of AZ names where NAT Gateways should be deployed"
  nullable    = false
  sensitive   = false
  ephemeral   = false
}

variable "enable_nat_gateway" {
  default     = true
  type        = bool
  description = "Flag to deploy NAT gateway"
  ephemeral   = false
  nullable    = false
  sensitive   = false
}

variable "bastion_allowed_cidr" {
  type        = string
  ephemeral   = false
  nullable    = false
  sensitive   = false
  description = "Bastion Instance IP CIDR's allowed"
}

/* K3s Cluster Variables */

# Pre-generate with: openssl rand -hex 32
# Set as a sensitive workspace variable in TF Cloud — do NOT put the value in terraform.tfvars
variable "k3s_token" {
  type        = string
  description = "k3s cluster join token used by both the server (install) and workers (join). Set as a sensitive variable in TF Cloud."
  sensitive   = true
  nullable    = false
}

variable "k3s_version" {
  type        = string
  description = "k3s version to install on all nodes"
  nullable    = false
}

/* DockerHub Variables */

variable "dockerhub_username" {
  type        = string
  description = "DockerHub username for image pulls (rate-limit bypass)"
  sensitive   = true
  nullable    = false
}

variable "dockerhub_token" {
  type        = string
  description = "DockerHub access token for image pulls"
  sensitive   = true
  nullable    = false
}

/* Ingress Variables */

variable "keepalived_auth_pass" {
  type        = string
  description = "Keepalived VRRP authentication password (max 8 chars)"
  sensitive   = true
  nullable    = false
}

variable "haproxy_stats_password" {
  type        = string
  description = "Password for HAProxy stats page (user: admin)"
  sensitive   = true
  nullable    = false
}

/* IAM / S3 Variables */

variable "route53_hosted_zone_id" {
  type        = string
  description = "Route53 hosted zone ID for cert-manager DNS-01 challenges"
  nullable    = false
}

variable "etcd_backup_bucket_name" {
  type        = string
  description = "S3 bucket name for k3s etcd snapshots. Defaults to <cluster_name>-etcd-backups."
  default     = null
  nullable    = true
}

variable "velero_backup_bucket_name" {
  type        = string
  description = "S3 bucket name for Velero cluster backups. Defaults to <cluster_name>-velero-backups."
  default     = null
  nullable    = true
}

variable "longhorn_backup_bucket_name" {
  type        = string
  description = "S3 bucket name for Longhorn volume backups. Defaults to <cluster_name>-longhorn-backups."
  default     = null
  nullable    = true
}

/* UI / App Passwords — written to ~/helm-secrets.env on bastion at provision time */

# Pre-generate with: openssl rand -base64 32
variable "rancher_bootstrap_password" {
  type        = string
  description = "Rancher initial bootstrap password (Helm --set bootstrapPassword). Change on first login."
  sensitive   = true
  nullable    = false
}

# Pre-generate with: htpasswd -nb admin $(openssl rand -base64 16) | base64
# The value stored here is the PLAIN password; bastion.sh runs htpasswd + base64 at boot.
variable "traefik_dashboard_password" {
  type        = string
  description = "Plain password for the Traefik dashboard basicAuth (user: admin). Hashed on the bastion at boot."
  sensitive   = true
  nullable    = false
}

variable "longhorn_ui_password" {
  type        = string
  description = "Plain password for Longhorn UI basicAuth (user: admin). Hashed on the bastion at boot."
  sensitive   = true
  nullable    = false
}

variable "grafana_admin_password" {
  type        = string
  description = "Grafana admin password for the kube-prometheus-stack Helm release."
  sensitive   = true
  nullable    = false
}

