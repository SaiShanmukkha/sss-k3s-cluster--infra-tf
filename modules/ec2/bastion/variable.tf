variable "cluster_name" {
  type    = string
  nullable = false
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "public_subnet_id" {
  description = "Public subnet ID for bastion (ap-south-1a)"
  type        = string
}

variable "admin_key_name" {
  description = "Admin keypair name for bastion SSH"
  type        = string
}

variable "bastion_sg_id" {
  description = "Security group ID for bastion"
  type        = string
}

variable "bastion_instance_profile" {
  description = "IAM instance profile name for bastion"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}