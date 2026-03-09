# =============================================================================
# 1. VPC
# =============================================================================

module "vpc" {
  source = "./modules/vpc"

  cluster_name            = local.cluster_name
  vpc_cidr                = var.vpc_cidr
  tags                    = local.common_tags
  public_subnet_cidrs     = var.public_subnet_cidrs
  private_subnet_cidrs    = var.private_subnet_cidrs
  enable_nat_gateway      = var.enable_nat_gateway
  public_nat_subnet_cidrs = var.public_nat_subnet_cidrs
}

# =============================================================================
# 2. Security Groups
# =============================================================================

module "security_groups" {
  source = "./modules/security-groups"

  cluster_name         = local.cluster_name
  vpc_id               = module.vpc.vpc_id
  bastion_allowed_cidr = var.bastion_allowed_cidr
  tags                 = local.common_tags
}

# =============================================================================
# 3. Key Pairs
# =============================================================================

module "keypair" {
  source = "./modules/keypair"

  cluster_name      = local.cluster_name
  save_keys_locally = true
  tags              = local.common_tags
}

# =============================================================================
# 4. IAM
# Bucket names resolved in locals to match S3 module defaults — avoids a
# circular dependency (IAM needs names for policy ARNs; S3 needs role ARNs).
# =============================================================================

module "iam" {
  source = "./modules/iam"

  cluster_name                = local.cluster_name
  tags                        = local.common_tags
  etcd_backup_bucket_name     = local.etcd_backup_bucket_name
  velero_backup_bucket_name   = local.velero_backup_bucket_name
  longhorn_backup_bucket_name = local.longhorn_backup_bucket_name
  route53_hosted_zone_id      = var.route53_hosted_zone_id
}

# =============================================================================
# 5. S3 Buckets (etcd backups, Velero, Longhorn)
# =============================================================================

module "s3" {
  source = "./modules/s3"

  cluster_name            = local.cluster_name
  aws_region              = var.region
  tags                    = local.common_tags
  vpc_id                  = module.vpc.vpc_id
  private_route_table_ids = module.vpc.private_route_table_ids
  k3s_server_role_arn     = module.iam.k3s_server_role_arn
  k3s_worker_role_arn     = module.iam.k3s_worker_role_arn

  # null = use cluster_name-based default names (matches local.* above)
  etcd_backup_bucket_name     = var.etcd_backup_bucket_name
  velero_backup_bucket_name   = var.velero_backup_bucket_name
  longhorn_backup_bucket_name = var.longhorn_backup_bucket_name
}

# =============================================================================
# 6. Ingress — HAProxy + Keepalived
# Must be created before k3s-server so the floating EIP exists and can be
# added to the k3s TLS SANs at install time.
# Server and worker IPs are taken from locals (fixed) to avoid a cycle.
# =============================================================================

module "ingress" {
  source = "./modules/ec2/ingress"

  cluster_name             = local.cluster_name
  public_subnet_ids        = module.vpc.public_subnet_ids
  internal_key_name        = module.keypair.internal_key_name
  ingress_sg_id            = module.security_groups.ingress_sg_id
  ingress_instance_profile = module.iam.ingress_instance_profile_name
  ingress_2_private_ip     = local.ingress_2_private_ip
  keepalived_auth_pass     = var.keepalived_auth_pass
  haproxy_stats_password   = var.haproxy_stats_password
  k3s_server_private_ips   = values(local.k3s_server_private_ips)
  k3s_worker_private_ips   = values(local.k3s_worker_private_ips)
  tags                     = local.common_tags
}

# =============================================================================
# 7. Bastion
# =============================================================================

module "bastion" {
  source = "./modules/ec2/bastion"

  cluster_name                = local.cluster_name
  public_subnet_id            = module.vpc.public_subnet_ids["ap-south-1a"]
  admin_key_name              = module.keypair.admin_key_name
  bastion_sg_id               = module.security_groups.bastion_sg_id
  bastion_instance_profile    = module.iam.bastion_instance_profile_name
  tags                        = local.common_tags
  rancher_bootstrap_password  = var.rancher_bootstrap_password
  traefik_dashboard_password  = var.traefik_dashboard_password
  longhorn_ui_password        = var.longhorn_ui_password
  grafana_admin_password      = var.grafana_admin_password
}

# =============================================================================
# 8. k3s Servers — 3-node HA control plane (etcd quorum)
# Init node (1a) starts with --cluster-init; secondaries join once init is up.
# =============================================================================

module "k3s_server_init" {
  source = "./modules/ec2/k3s-server"

  cluster_name                = local.cluster_name
  node_name                   = local.k3s_server_node_names["ap-south-1a"]
  private_subnet_id           = module.vpc.private_subnet_ids["ap-south-1a"]
  private_ip                  = local.k3s_server_private_ips["ap-south-1a"]
  internal_key_name           = module.keypair.internal_key_name
  k3s_server_sg_id            = module.security_groups.k3s_server_sg_id
  k3s_server_instance_profile = module.iam.k3s_server_instance_profile_name
  ingress_eip                 = module.ingress.ingress_eip
  k3s_version                 = var.k3s_version
  k3s_token                   = var.k3s_token
  etcd_backup_bucket_name     = local.etcd_backup_bucket_name
  aws_region                  = var.region
  dockerhub_username          = var.dockerhub_username
  dockerhub_token             = var.dockerhub_token
  is_init_node                = true
  tags                        = local.common_tags
}

module "k3s_servers_secondary" {
  for_each = local.k3s_server_secondary_ips

  source = "./modules/ec2/k3s-server"

  cluster_name                = local.cluster_name
  node_name                   = local.k3s_server_node_names[each.key]
  private_subnet_id           = module.vpc.private_subnet_ids[each.key]
  private_ip                  = each.value
  internal_key_name           = module.keypair.internal_key_name
  k3s_server_sg_id            = module.security_groups.k3s_server_sg_id
  k3s_server_instance_profile = module.iam.k3s_server_instance_profile_name
  ingress_eip                 = module.ingress.ingress_eip
  k3s_version                 = var.k3s_version
  k3s_token                   = var.k3s_token
  etcd_backup_bucket_name     = local.etcd_backup_bucket_name
  aws_region                  = var.region
  dockerhub_username          = var.dockerhub_username
  dockerhub_token             = var.dockerhub_token
  is_init_node                = false
  init_node_ip                = local.k3s_server_private_ips["ap-south-1a"]
  tags                        = local.common_tags

  depends_on = [module.k3s_server_init]
}

# =============================================================================
# 9. k3s Workers (3x spot instances, one per AZ)
# Depends on k3s_server so the server is ready before workers try to join.
# =============================================================================

module "k3s_workers" {
  source = "./modules/ec2/k3s-worker"

  cluster_name                = local.cluster_name
  private_subnet_ids          = module.vpc.private_subnet_ids
  worker_private_ips          = local.k3s_worker_private_ips
  internal_key_name           = module.keypair.internal_key_name
  k3s_worker_sg_id            = module.security_groups.k3s_worker_sg_id
  k3s_worker_instance_profile = module.iam.k3s_worker_instance_profile_name
  k3s_server_ip               = local.k3s_server_private_ip
  k3s_token                   = var.k3s_token
  k3s_version                 = var.k3s_version
  dockerhub_username          = var.dockerhub_username
  dockerhub_token             = var.dockerhub_token
  tags                        = local.common_tags

  depends_on = [module.k3s_server_init]
}
