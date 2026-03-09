# =============================================================================
# modules/ec2/k3s-worker/main.tf
# 3x k3s worker nodes — one per AZ
# Rocky Linux 9, t3a.large (AMD Spot instances)
# Each node has 2 EBS volumes: root + dedicated Longhorn disk
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

locals {
  # Workers are keyed worker-1/2/3 in AZ sort order (ap-south-1a → worker-1, etc.)
  workers = {
    for idx, az in tolist(sort(keys(var.private_subnet_ids))) :
    "worker-${idx + 1}" => {
      subnet_id  = var.private_subnet_ids[az]
      private_ip = var.worker_private_ips[az]
      az         = az
    }
  }
}

resource "aws_spot_instance_request" "k3s_worker" {
  for_each = local.workers

  ami                            = data.aws_ami.rocky9.id
  instance_type                  = var.instance_type
  subnet_id                      = each.value.subnet_id
  key_name                       = var.internal_key_name
  vpc_security_group_ids         = [var.k3s_worker_sg_id]
  iam_instance_profile           = var.k3s_worker_instance_profile
  private_ip                     = each.value.private_ip
  spot_type                      = "persistent"
  instance_interruption_behavior = "stop"  # stop on interruption, not terminate
  wait_for_fulfillment           = true
  spot_price                     = var.spot_price

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50
    encrypted             = true
    delete_on_termination = true

    tags = merge(var.tags, {
      Name = "${var.cluster_name}-${each.key}-root"
    })
  }

  user_data = base64encode(templatefile("${path.module}/userdata/k3s-worker.sh", {
    cluster_name       = var.cluster_name
    k3s_version        = var.k3s_version
    k3s_server_ip      = var.k3s_server_ip
    k3s_token          = var.k3s_token
    worker_name        = each.key
    worker_private_ip  = each.value.private_ip
    dockerhub_username = var.dockerhub_username
    dockerhub_token    = var.dockerhub_token
    longhorn_disk      = "/dev/nvme1n1"
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-${each.key}"
    Role = "k3s-worker"
    AZ   = each.value.az
  })
}

# Dedicated Longhorn EBS disk — separate from root
resource "aws_ebs_volume" "longhorn" {
  for_each = local.workers

  availability_zone = each.value.az
  size              = var.longhorn_disk_size
  type              = "gp3"
  encrypted         = true

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-${each.key}-longhorn"
    Purpose = "longhorn-storage"
  })
}

resource "aws_volume_attachment" "longhorn" {
  for_each = local.workers

  device_name  = "/dev/sdf"
  volume_id    = aws_ebs_volume.longhorn[each.key].id
  instance_id  = aws_spot_instance_request.k3s_worker[each.key].spot_instance_id
  force_detach = false
}

# aws_spot_instance_request.tags only tag the request, NOT the launched EC2 instance.
# These aws_ec2_tag resources apply the key tags to the actual running instance.
resource "aws_ec2_tag" "worker_name" {
  for_each    = local.workers
  resource_id = aws_spot_instance_request.k3s_worker[each.key].spot_instance_id
  key         = "Name"
  value       = "${var.cluster_name}-${each.key}"
}

resource "aws_ec2_tag" "worker_role" {
  for_each    = local.workers
  resource_id = aws_spot_instance_request.k3s_worker[each.key].spot_instance_id
  key         = "Role"
  value       = "k3s-worker"
}

resource "aws_ec2_tag" "worker_az" {
  for_each    = local.workers
  resource_id = aws_spot_instance_request.k3s_worker[each.key].spot_instance_id
  key         = "AZ"
  value       = each.value.az
}