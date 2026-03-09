# =============================================================================
# VPC
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Map of AZ to public subnet ID"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Map of AZ to private subnet ID"
  value       = module.vpc.private_subnet_ids
}

output "nat_gateway_ids" {
  description = "Map of AZ to NAT Gateway ID"
  value       = module.vpc.nat_gateway_ids
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = module.vpc.internet_gateway_id
}

# =============================================================================
# Bastion
# =============================================================================

output "bastion_public_ip" {
  description = "Bastion Elastic IP — SSH entrypoint"
  value       = module.bastion.bastion_public_ip
}

output "bastion_instance_id" {
  description = "Bastion EC2 instance ID"
  value       = module.bastion.bastion_instance_id
}

# =============================================================================
# Ingress
# =============================================================================

output "ingress_eip" {
  description = "Floating ingress EIP — point your DNS wildcard (*.domain) here"
  value       = module.ingress.ingress_eip
}

output "ingress_1_public_ip" {
  description = "ingress-1 node public IP (management)"
  value       = module.ingress.ingress_1_public_ip
}

output "ingress_2_public_ip" {
  description = "ingress-2 node public IP (management)"
  value       = module.ingress.ingress_2_public_ip
}

# =============================================================================
# k3s Server
# =============================================================================

output "k3s_server_instance_ids" {
  description = "Map of AZ to k3s server EC2 instance ID (all 3 control-plane nodes)"
  value = merge(
    { "ap-south-1a" = module.k3s_server_init.server_instance_id },
    { for az, m in module.k3s_servers_secondary : az => m.server_instance_id }
  )
}

output "k3s_server_private_ips" {
  description = "Map of AZ to k3s server private IP (all 3 control-plane nodes)"
  value = merge(
    { "ap-south-1a" = module.k3s_server_init.server_private_ip },
    { for az, m in module.k3s_servers_secondary : az => m.server_private_ip }
  )
}

# =============================================================================
# k3s Workers
# =============================================================================

output "k3s_worker_instance_ids" {
  description = "Map of worker name to spot instance ID"
  value       = module.k3s_workers.worker_instance_ids
}

output "k3s_worker_private_ips" {
  description = "Map of worker name to private IP"
  value       = module.k3s_workers.worker_private_ips
}

output "longhorn_volume_ids" {
  description = "Map of worker name to Longhorn EBS volume ID"
  value       = module.k3s_workers.longhorn_volume_ids
}

# =============================================================================
# S3
# =============================================================================

output "etcd_backup_bucket" {
  description = "S3 bucket name for k3s etcd snapshots"
  value       = module.s3.etcd_backup_bucket_name
}

output "velero_backup_bucket" {
  description = "S3 bucket name for Velero backups"
  value       = module.s3.velero_backup_bucket_name
}

output "longhorn_backup_bucket" {
  description = "S3 bucket name for Longhorn volume backups"
  value       = module.s3.longhorn_backup_bucket_name
}

output "longhorn_s3_access_key_id" {
  description = "Longhorn IAM user access key — put in longhorn-s3-secret"
  value       = module.iam.longhorn_s3_access_key_id
  sensitive   = true
}

output "longhorn_s3_secret_access_key" {
  description = "Longhorn IAM user secret key — put in longhorn-s3-secret"
  value       = module.iam.longhorn_s3_secret_access_key
  sensitive   = true
}

# =============================================================================
# SSH Key material (sensitive)
# =============================================================================

output "admin_private_key_pem" {
  description = "Admin private key PEM — for bastion SSH (also written to keys/ locally)"
  value       = module.keypair.admin_private_key_pem
  sensitive   = true
}

output "internal_private_key_pem" {
  description = "Internal private key PEM — for server/worker/ingress SSH (also written to keys/ locally)"
  value       = module.keypair.internal_private_key_pem
  sensitive   = true
}

# =============================================================================
# IAM Role ARNs (useful for kubectl RBAC / CI-CD)
# =============================================================================

output "k3s_server_role_arn" {
  description = "IAM role ARN for k3s server nodes"
  value       = module.iam.k3s_server_role_arn
}

output "k3s_worker_role_arn" {
  description = "IAM role ARN for k3s worker nodes"
  value       = module.iam.k3s_worker_role_arn
}


