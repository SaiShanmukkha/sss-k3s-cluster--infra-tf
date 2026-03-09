variable "cluster_name" {
  type    = string
  default = "sss"
}

variable "vpc_id" {
  description = "VPC ID where security groups are created"
  type        = string
}

variable "bastion_allowed_cidr" {
  description = "CIDR allowed to SSH into bastion and reach the kubectl API via ingress"
  type        = string
  default     = "0.0.0.0/0"
}

variable "tags" {
  type    = map(string)
  default = {}
}