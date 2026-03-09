variable "cluster_name" {
  type    = string
  nullable = false
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "private_subnet_id" {
  description = "Private subnet ID for server node (ap-south-1a)"
  type        = string
}

variable "private_ip" {
  description = "Fixed private IP for server node (must be within private subnet ap-south-1a: 10.0.11.0/24)"
  type        = string
  default     = "10.0.11.10"
}

variable "internal_key_name" {
  type = string
}

variable "k3s_server_sg_id" {
  type = string
}

variable "k3s_server_instance_profile" {
  type = string
}

variable "ingress_eip" {
  description = "Ingress floating EIP — added to k3s TLS SANs"
  type        = string
}

variable "k3s_version" {
  description = "k3s version to install"
  type        = string
  nullable    = false
}

variable "etcd_backup_bucket_name" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "ap-south-1"
}

variable "dockerhub_username" {
  description = "DockerHub username for image pulls"
  type        = string
  sensitive   = true
}

variable "dockerhub_token" {
  description = "DockerHub access token for image pulls"
  type        = string
  sensitive   = true
}

variable "disable_traefik" {
  description = "Disable built-in Traefik (install via Helm instead)"
  type        = bool
  default     = true
}

variable "k3s_token" {
  description = "Pre-defined k3s cluster join token. Set as a sensitive variable in TF Cloud."
  type        = string
  sensitive   = true
  nullable    = false
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "is_init_node" {
  description = "If true, starts with --cluster-init (etcd leader). If false, joins existing cluster via --server."
  type        = bool
  default     = true
}

variable "init_node_ip" {
  description = "Private IP of the --cluster-init server. Required when is_init_node = false."
  type        = string
  default     = ""
}

variable "node_name" {
  description = "Node name for hostname and EC2 Name tag (e.g. k3s-server-1)"
  type        = string
  default     = "k3s-server-1"
}