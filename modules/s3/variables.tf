variable "cluster_name" {
  type    = string
  default = "sss"
}

variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "vpc_id" {
  description = "VPC ID for S3 gateway endpoint"
  type        = string
}

variable "private_route_table_ids" {
  description = "Private route table IDs — S3 gateway endpoint added to these"
  type        = list(string)
}

variable "k3s_server_role_arn" {
  description = "k3s server IAM role ARN — allowed to access etcd bucket"
  type        = string
}

variable "k3s_worker_role_arn" {
  description = "k3s worker IAM role ARN — allowed to access velero + longhorn buckets"
  type        = string
}

variable "etcd_backup_bucket_name" {
  type    = string
  default = null
}

variable "velero_backup_bucket_name" {
  type    = string
  default = null
}

variable "longhorn_backup_bucket_name" {
  type    = string
  default = null
}