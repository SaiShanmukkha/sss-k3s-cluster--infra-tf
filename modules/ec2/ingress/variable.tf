variable "cluster_name" {
  type    = string
  nullable = false
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "public_subnet_ids" {
  description = "Map of AZ => public subnet ID. Pass module.vpc.public_subnet_ids directly."
  type        = map(string)
}

variable "ingress_1_az" {
  description = "AZ for ingress-1 (Keepalived MASTER). Must be a key in public_subnet_ids."
  type        = string
  default     = "ap-south-1a"
}

variable "ingress_2_az" {
  description = "AZ for ingress-2 (Keepalived BACKUP). Must be a key in public_subnet_ids."
  type        = string
  default     = "ap-south-1b"
}

variable "internal_key_name" {
  description = "Internal keypair name"
  type        = string
}

variable "ingress_sg_id" {
  description = "Security group ID for ingress nodes"
  type        = string
}

variable "ingress_instance_profile" {
  description = "IAM instance profile for ingress nodes"
  type        = string
}

variable "ingress_2_private_ip" {
  description = "Fixed private IP for ingress-2 node (must be within public subnet ap-south-1b: 10.0.2.0/24); used in ingress-1 Keepalived unicast peer and enforced on the instance"
  type        = string
  default     = "10.0.2.10"
}

variable "keepalived_auth_pass" {
  description = "Keepalived VRRP authentication password (max 8 chars)"
  type        = string
  sensitive   = true
}

variable "haproxy_stats_password" {
  description = "Password for HAProxy stats page (user: admin)"
  type        = string
  sensitive   = true
}

variable "k3s_server_private_ips" {
  description = "List of k3s server private IPs for HAProxy backend"
  type        = list(string)
}

variable "k3s_worker_private_ips" {
  description = "List of k3s worker private IPs for HAProxy backend"
  type        = list(string)
}

variable "traefik_http_nodeport" {
  description = "Traefik HTTP NodePort on workers"
  type        = number
  default     = 30080
}

variable "traefik_https_nodeport" {
  description = "Traefik HTTPS NodePort on workers"
  type        = number
  default     = 30443
}

variable "tags" {
  type    = map(string)
  default = {}
}