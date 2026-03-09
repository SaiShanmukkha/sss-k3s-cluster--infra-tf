# =============================================================================
# modules/ec2/k3s-server/main.tf
# k3s control plane node
# Rocky Linux 9, t3.medium
# Starts with --cluster-init (etcd mode, HA-ready from day 1)
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

resource "aws_instance" "k3s_server" {
  ami                    = data.aws_ami.rocky9.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_id
  key_name               = var.internal_key_name
  vpc_security_group_ids = [var.k3s_server_sg_id]
  iam_instance_profile   = var.k3s_server_instance_profile

  # Fixed private IP — workers and ingress need to know this
  private_ip = var.private_ip

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    encrypted             = true
    delete_on_termination = false  # keep on termination — protect etcd data

    tags = merge(var.tags, {
      Name = "${var.cluster_name}-${var.node_name}-root"
    })
  }

  user_data = base64encode(templatefile("${path.module}/userdata/k3s-server.sh", {
    cluster_name          = var.cluster_name
    node_name             = var.node_name
    k3s_version           = var.k3s_version
    k3s_token             = var.k3s_token
    ingress_eip           = var.ingress_eip
    server_private_ip     = var.private_ip
    etcd_backup_bucket    = var.etcd_backup_bucket_name
    aws_region            = var.aws_region
    dockerhub_username    = var.dockerhub_username
    dockerhub_token       = var.dockerhub_token
    disable_traefik       = var.disable_traefik
    is_init_node          = var.is_init_node
    init_node_ip          = var.init_node_ip
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2  # 2 needed for pods to access IMDS
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-${var.node_name}"
    Role = "k3s-server"
  })
}