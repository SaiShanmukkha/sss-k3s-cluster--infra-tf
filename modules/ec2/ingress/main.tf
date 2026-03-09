# =============================================================================
# modules/ec2/ingress/main.tf
# 2x HAProxy ingress nodes in public subnets
# Keepalived for EIP failover between them
# Rocky Linux 9, t3.small
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

data "aws_ami" "rocky9" {
  most_recent = true
  owners      = ["679593333241"]

  filter {
    name   = "name"
    values = ["Rocky-9-EC2-Base-9.*x86_64*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Elastic IP — floats between ingress-1 and ingress-2 via Keepalived
resource "aws_eip" "ingress" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-ingress-eip"
    Purpose = "floating-vip-keepalived"
  })
}

# ingress-1 — primary (MASTER in Keepalived)
resource "aws_instance" "ingress_1" {
  ami                         = data.aws_ami.rocky9.id
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnet_ids[var.ingress_1_az]
  key_name                    = var.internal_key_name
  vpc_security_group_ids      = [var.ingress_sg_id]
  iam_instance_profile        = var.ingress_instance_profile
  associate_public_ip_address = true  # needs own public IP for mgmt

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true

    tags = merge(var.tags, {
      Name = "${var.cluster_name}-ingress-1-root"
    })
  }

  user_data = base64encode(templatefile("${path.module}/userdata/ingress.sh", {
    cluster_name           = var.cluster_name
    node_index             = "1"
    keepalived_role        = "MASTER"
    keepalived_priority    = "101"
    peer_ip                = var.ingress_2_private_ip
    eip_allocation_id      = aws_eip.ingress.allocation_id
    k3s_server_ips         = join(",", var.k3s_server_private_ips)
    traefik_http_port      = var.traefik_http_nodeport
    traefik_https_port     = var.traefik_https_nodeport
    worker_ips             = join(",", var.k3s_worker_private_ips)
    keepalived_auth_pass   = var.keepalived_auth_pass
    haproxy_stats_password = var.haproxy_stats_password
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-ingress-1"
    Role = "ingress"
  })
}

# ingress-2 — secondary (BACKUP in Keepalived)
resource "aws_instance" "ingress_2" {
  ami                         = data.aws_ami.rocky9.id
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnet_ids[var.ingress_2_az]
  key_name                    = var.internal_key_name
  vpc_security_group_ids      = [var.ingress_sg_id]
  iam_instance_profile        = var.ingress_instance_profile
  associate_public_ip_address = true

  # Fixed IP so ingress-1 Keepalived peer config matches the actual instance IP
  private_ip = var.ingress_2_private_ip

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true

    tags = merge(var.tags, {
      Name = "${var.cluster_name}-ingress-2-root"
    })
  }

  user_data = base64encode(templatefile("${path.module}/userdata/ingress.sh", {
    cluster_name           = var.cluster_name
    node_index             = "2"
    keepalived_role        = "BACKUP"
    keepalived_priority    = "100"
    peer_ip                = aws_instance.ingress_1.private_ip
    eip_allocation_id      = aws_eip.ingress.allocation_id
    k3s_server_ips         = join(",", var.k3s_server_private_ips)
    traefik_http_port      = var.traefik_http_nodeport
    traefik_https_port     = var.traefik_https_nodeport
    worker_ips             = join(",", var.k3s_worker_private_ips)
    keepalived_auth_pass   = var.keepalived_auth_pass
    haproxy_stats_password = var.haproxy_stats_password
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-ingress-2"
    Role = "ingress"
  })
}

# Associate EIP to ingress-1 initially (Keepalived manages failover after)
resource "aws_eip_association" "ingress" {
  instance_id   = aws_instance.ingress_1.id
  allocation_id = aws_eip.ingress.allocation_id
}