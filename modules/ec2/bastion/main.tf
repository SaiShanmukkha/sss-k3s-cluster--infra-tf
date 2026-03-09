# =============================================================================
# modules/ec2/bastion/main.tf
# Single bastion host in public subnet
# Rocky Linux 9, t3.micro, admin keypair
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
  owners      = ["679593333241"] # Rocky Linux official AWS account

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

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.rocky9.id
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnet_id
  key_name                    = var.admin_key_name
  vpc_security_group_ids      = [var.bastion_sg_id]
  iam_instance_profile        = var.bastion_instance_profile
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true

    tags = merge(var.tags, {
      Name = "${var.cluster_name}-bastion-root"
    })
  }

  user_data = base64encode(templatefile("${path.module}/userdata/bastion.sh", {
    cluster_name = var.cluster_name
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 enforced
    http_put_response_hop_limit = 1
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-bastion"
    Role = "bastion"
  })
}

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  domain   = "vpc"

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-bastion-eip"
  })
}