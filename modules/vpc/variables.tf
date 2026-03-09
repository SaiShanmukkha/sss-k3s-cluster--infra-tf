variable "cluster_name"{
    type = string
    description = "Name prefix for resources"
    nullable = false
    sensitive = false
    ephemeral = false
}

variable "vpc_cidr" {
    type = string
    description = "CIDR block for the VPC"
    nullable = false
    sensitive = false
    ephemeral = false
}

variable "tags" {
  type = map(string)
  description = "Common Tags Across all Resources"
  default = {}
}

variable "public_subnet_cidrs" {
    type = map(string)
    description = "List of CIDR blocks for public subnets"
    nullable = false
    sensitive = false
    ephemeral = false
}

 variable "private_subnet_cidrs" {
    type = map(string)
    description = "List of CIDR blocks for private subnets."
    nullable = false
    sensitive = false
    ephemeral = false
}

variable "enable_nat_gateway" {
    type = bool
    description = "Whether to enable NAT gateway"
    nullable = false
    sensitive = false
    ephemeral = false
}

variable "public_nat_subnet_cidrs" {
    type        = set(string)
    description = "Set of AZ names where NAT Gateways should be deployed (e.g. [\"us-east-1a\", \"us-east-1b\"])"
    nullable    = false
    sensitive   = false
    ephemeral   = false
}


