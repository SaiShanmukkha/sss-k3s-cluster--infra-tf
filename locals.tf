locals {
  cluster_name = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Cluster     = local.cluster_name
  }

  # ── Fixed private IPs ───────────────────────────────────────────────────────
  # These are used by multiple modules. Defining them here keeps a single
  # source of truth and avoids circular module dependencies.

  # Init node alias — used by workers (K3S_URL) and as etcd primary reference
  k3s_server_private_ip = "10.0.11.10"

  # All 3 control-plane IPs — one per AZ for etcd quorum
  k3s_server_private_ips = {
    "ap-south-1a" = "10.0.11.10" # init node (--cluster-init)
    "ap-south-1b" = "10.0.12.10" # secondary
    "ap-south-1c" = "10.0.13.10" # secondary
  }

  # Secondary nodes only — used by for_each in main.tf
  k3s_server_secondary_ips = {
    "ap-south-1b" = "10.0.12.10"
    "ap-south-1c" = "10.0.13.10"
  }

  # Node name map — used for hostname and EC2 Name tag
  k3s_server_node_names = {
    "ap-south-1a" = "k3s-server-1" # TODO: change to server-1
    "ap-south-1b" = "k3s-server-2" # TODO: change to server-2
    "ap-south-1c" = "k3s-server-3" # TODO: change to server-3
  }

  # One worker per AZ — keys must match private_subnet_cidrs AZ keys
  k3s_worker_private_ips = {
    "ap-south-1a" = "10.0.11.20"
    "ap-south-1b" = "10.0.12.20"
    "ap-south-1c" = "10.0.13.20"
  }

  # ingress-2 fixed IP (ap-south-1b public subnet: 10.0.2.0/24)
  ingress_2_private_ip = "10.0.2.10"

  # ── S3 bucket names ─────────────────────────────────────────────────────────
  # Computed here so the IAM module can reference final names without depending
  # on the S3 module (which in turn depends on IAM — would create a cycle).
  # Formula mirrors the coalesce() in modules/s3/main.tf.

  etcd_backup_bucket_name     = coalesce(var.etcd_backup_bucket_name, "${local.cluster_name}-etcd-backups")
  velero_backup_bucket_name   = coalesce(var.velero_backup_bucket_name, "${local.cluster_name}-velero-backups")
  longhorn_backup_bucket_name = coalesce(var.longhorn_backup_bucket_name, "${local.cluster_name}-longhorn-backups")
}