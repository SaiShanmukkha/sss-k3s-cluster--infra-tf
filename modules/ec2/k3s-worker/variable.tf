variable "cluster_name" {
  type    = string
  nullable = false
}

variable "instance_type" {
  type    = string
  default = "t3a.large"
}

variable "private_subnet_ids" {
  description = "Map of AZ => private subnet ID. Pass module.vpc.private_subnet_ids directly."
  type        = map(string)
}

variable "worker_private_ips" {
  description = "Map of AZ => fixed private IP for each worker. Keys must match private_subnet_ids."
  type        = map(string)
  default = {
    "ap-south-1a" = "10.0.11.20"
    "ap-south-1b" = "10.0.12.20"
    "ap-south-1c" = "10.0.13.20"
  }
}

variable "internal_key_name" {
  type = string
}

variable "k3s_worker_sg_id" {
  type = string
}

variable "k3s_worker_instance_profile" {
  type = string
}

variable "k3s_server_ip" {
  description = "k3s server private IP — workers connect here"
  type        = string
}

variable "k3s_token" {
  description = "k3s join token from server node"
  type        = string
  sensitive   = true
}

variable "k3s_version" {
  type    = string
  nullable = false
}

variable "longhorn_disk_size" {
  description = "Longhorn dedicated EBS disk size in GB"
  type        = number
  default     = 50
}

variable "spot_price" {
  description = "Maximum hourly spot price. Default is ~95% of t3a.large on-demand in ap-south-1 ($0.0752 * 0.95). Recalculate if you change instance_type or region."
  type        = string
  default     = "0.0714"
}

variable "dockerhub_username" {
  type      = string
  sensitive = true
}

variable "dockerhub_token" {
  type      = string
  sensitive = true
}

variable "tags" {
  type    = map(string)
  default = {}
}