# =============================================================================
# modules/iam/main.tf
# 4 IAM roles + instance profiles. Zero hardcoded credentials.
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# =============================================================================
# SHARED — EC2 assume role policy
# =============================================================================

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# =============================================================================
# SHARED — SSM Session Manager (attached to all 4 roles)
# =============================================================================

data "aws_iam_policy_document" "ssm_session_manager" {
  statement {
    sid    = "SSMSessionManager"
    effect = "Allow"
    actions = [
      "ssm:StartSession",
      "ssm:TerminateSession",
      "ssm:ResumeSession",
      "ssm:DescribeSessions",
      "ssm:GetConnectionStatus",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ssm_session_manager" {
  name        = "${var.cluster_name}-ssm-session-manager"
  description = "SSM Session Manager access for all cluster nodes"
  policy      = data.aws_iam_policy_document.ssm_session_manager.json
  tags        = var.tags
}

# =============================================================================
# 1. K3S SERVER ROLE
# =============================================================================

data "aws_iam_policy_document" "k3s_server" {

  # S3 etcd backup — bucket level
  statement {
    sid    = "S3EtcdBackupBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = ["arn:aws:s3:::${var.etcd_backup_bucket_name}"]
  }

  # S3 etcd backup — object level
  statement {
    sid    = "S3EtcdBackupObjects"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload"
    ]
    resources = ["arn:aws:s3:::${var.etcd_backup_bucket_name}/*"]
  }

  # Route53 — cert-manager DNS-01
  statement {
    sid       = "Route53GetChange"
    effect    = "Allow"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    sid    = "Route53ManageRecords"
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets"
    ]
    resources = ["arn:aws:route53:::hostedzone/${var.route53_hosted_zone_id}"]
  }

  statement {
    sid       = "Route53ListZones"
    effect    = "Allow"
    actions   = ["route53:ListHostedZonesByName", "route53:ListHostedZones"]
    resources = ["*"]
  }

  # EC2 describe — cloud provider
  statement {
    sid    = "EC2Describe"
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ec2:DescribeAvailabilityZones"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "k3s_server" {
  name        = "${var.cluster_name}-k3s-server-policy"
  description = "Policy for k3s control plane nodes"
  policy      = data.aws_iam_policy_document.k3s_server.json
  tags        = var.tags
}

resource "aws_iam_role" "k3s_server" {
  name               = "${var.cluster_name}-k3s-server-role"
  description        = "IAM role for k3s control plane nodes"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags = merge(var.tags, {
    Name = "${var.cluster_name}-k3s-server-role"
    Role = "k3s-server"
  })
}

resource "aws_iam_role_policy_attachment" "k3s_server_main" {
  role       = aws_iam_role.k3s_server.name
  policy_arn = aws_iam_policy.k3s_server.arn
}

resource "aws_iam_role_policy_attachment" "k3s_server_ssm" {
  role       = aws_iam_role.k3s_server.name
  policy_arn = aws_iam_policy.ssm_session_manager.arn
}

resource "aws_iam_instance_profile" "k3s_server" {
  name = "${var.cluster_name}-k3s-server-profile"
  role = aws_iam_role.k3s_server.name
  tags = merge(var.tags, {
    Name = "${var.cluster_name}-k3s-server-profile"
  })
}

# =============================================================================
# 2. K3S WORKER ROLE
# =============================================================================

data "aws_iam_policy_document" "k3s_worker" {

  # Longhorn — EBS describe only
  statement {
    sid    = "LonghornEBSDescribe"
    effect = "Allow"
    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeVolumeStatus",
      "ec2:DescribeVolumeAttribute",
      "ec2:DescribeInstances",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeTags"
    ]
    resources = ["*"]
  }

  # S3 Velero — bucket
  statement {
    sid    = "S3VeleroBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads"
    ]
    resources = ["arn:aws:s3:::${var.velero_backup_bucket_name}"]
  }

  # S3 Velero — objects
  statement {
    sid    = "S3VeleroObjects"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload"
    ]
    resources = ["arn:aws:s3:::${var.velero_backup_bucket_name}/*"]
  }

  # S3 Longhorn — bucket
  statement {
    sid    = "S3LonghornBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads"
    ]
    resources = ["arn:aws:s3:::${var.longhorn_backup_bucket_name}"]
  }

  # S3 Longhorn — objects
  statement {
    sid    = "S3LonghornObjects"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload"
    ]
    resources = ["arn:aws:s3:::${var.longhorn_backup_bucket_name}/*"]
  }
}

resource "aws_iam_policy" "k3s_worker" {
  name        = "${var.cluster_name}-k3s-worker-policy"
  description = "Policy for k3s worker nodes"
  policy      = data.aws_iam_policy_document.k3s_worker.json
  tags        = var.tags
}

resource "aws_iam_role" "k3s_worker" {
  name               = "${var.cluster_name}-k3s-worker-role"
  description        = "IAM role for k3s worker nodes"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags = merge(var.tags, {
    Name = "${var.cluster_name}-k3s-worker-role"
    Role = "k3s-worker"
  })
}

resource "aws_iam_role_policy_attachment" "k3s_worker_main" {
  role       = aws_iam_role.k3s_worker.name
  policy_arn = aws_iam_policy.k3s_worker.arn
}

resource "aws_iam_role_policy_attachment" "k3s_worker_ssm" {
  role       = aws_iam_role.k3s_worker.name
  policy_arn = aws_iam_policy.ssm_session_manager.arn
}

resource "aws_iam_instance_profile" "k3s_worker" {
  name = "${var.cluster_name}-k3s-worker-profile"
  role = aws_iam_role.k3s_worker.name
  tags = merge(var.tags, {
    Name = "${var.cluster_name}-k3s-worker-profile"
  })
}

# =============================================================================
# LONGHORN S3 IAM USER
# Longhorn v1.7+ requires explicit credentials in the Kubernetes secret —
# it does NOT fall back to the EC2 instance profile even when keys are absent.
# =============================================================================

resource "aws_iam_user" "longhorn_s3" {
  name = "${var.cluster_name}-longhorn-s3"
  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-longhorn-s3"
    Purpose = "longhorn-backup-target"
  })
}

data "aws_iam_policy_document" "longhorn_s3" {
  statement {
    sid    = "LonghornS3Bucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads"
    ]
    resources = ["arn:aws:s3:::${var.longhorn_backup_bucket_name}"]
  }

  statement {
    sid    = "LonghornS3Objects"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload"
    ]
    resources = ["arn:aws:s3:::${var.longhorn_backup_bucket_name}/*"]
  }
}

resource "aws_iam_user_policy" "longhorn_s3" {
  name   = "${var.cluster_name}-longhorn-s3-policy"
  user   = aws_iam_user.longhorn_s3.name
  policy = data.aws_iam_policy_document.longhorn_s3.json
}

resource "aws_iam_access_key" "longhorn_s3" {
  user = aws_iam_user.longhorn_s3.name
}

# =============================================================================
# 3. INGRESS ROLE
# =============================================================================

data "aws_iam_policy_document" "ingress" {
  statement {
    sid    = "EIPFailover"
    effect = "Allow"
    actions = [
      "ec2:DescribeAddresses",
      "ec2:AssociateAddress",
      "ec2:DisassociateAddress",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeNetworkInterfaceAttribute"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ingress" {
  name        = "${var.cluster_name}-ingress-policy"
  description = "Policy for ingress/HAProxy nodes"
  policy      = data.aws_iam_policy_document.ingress.json
  tags        = var.tags
}

resource "aws_iam_role" "ingress" {
  name               = "${var.cluster_name}-ingress-role"
  description        = "IAM role for ingress/HAProxy nodes"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags = merge(var.tags, {
    Name = "${var.cluster_name}-ingress-role"
    Role = "ingress"
  })
}

resource "aws_iam_role_policy_attachment" "ingress_main" {
  role       = aws_iam_role.ingress.name
  policy_arn = aws_iam_policy.ingress.arn
}

resource "aws_iam_role_policy_attachment" "ingress_ssm" {
  role       = aws_iam_role.ingress.name
  policy_arn = aws_iam_policy.ssm_session_manager.arn
}

resource "aws_iam_instance_profile" "ingress" {
  name = "${var.cluster_name}-ingress-profile"
  role = aws_iam_role.ingress.name
  tags = merge(var.tags, {
    Name = "${var.cluster_name}-ingress-profile"
  })
}

# =============================================================================
# 4. BASTION ROLE
# =============================================================================

resource "aws_iam_role" "bastion" {
  name               = "${var.cluster_name}-bastion-role"
  description        = "IAM role for bastion - SSM only"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags = merge(var.tags, {
    Name = "${var.cluster_name}-bastion-role"
    Role = "bastion"
  })
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = aws_iam_policy.ssm_session_manager.arn
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.cluster_name}-bastion-profile"
  role = aws_iam_role.bastion.name
  tags = merge(var.tags, {
    Name = "${var.cluster_name}-bastion-profile"
  })
}

