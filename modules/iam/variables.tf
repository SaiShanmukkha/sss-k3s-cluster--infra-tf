variable "cluster_name" {
  type    = string
  default = "sss-k8s"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "etcd_backup_bucket_name" {
  description = "S3 bucket for k3s etcd snapshots"
  type        = string
}

variable "velero_backup_bucket_name" {
  description = "S3 bucket for Velero cluster backups"
  type        = string
}

variable "longhorn_backup_bucket_name" {
  description = "S3 bucket for Longhorn volume backups"
  type        = string
}

variable "route53_hosted_zone_id" {
  description = "Route53 hosted zone ID for cert-manager DNS-01"
  type        = string
}

