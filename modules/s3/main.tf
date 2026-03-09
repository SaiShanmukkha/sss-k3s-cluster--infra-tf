# =============================================================================
# modules/s3/main.tf
# 3 buckets:
#   1. etcd-backups    → k3s control plane snapshots (CRITICAL)
#   2. velero-backups  → full cluster backup
#   3. longhorn-backups→ persistent volume backups
# All buckets:
#   - versioning enabled
#   - encryption at rest (SSE-S3)
#   - public access fully blocked
#   - lifecycle policies to control cost
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

locals {
  etcd_backup_bucket_name     = coalesce(var.etcd_backup_bucket_name, "${var.cluster_name}-etcd-backups")
  velero_backup_bucket_name   = coalesce(var.velero_backup_bucket_name, "${var.cluster_name}-velero-backups")
  longhorn_backup_bucket_name = coalesce(var.longhorn_backup_bucket_name, "${var.cluster_name}-longhorn-backups")
}

# =============================================================================
# 1. ETCD BACKUP BUCKET
# =============================================================================

resource "aws_s3_bucket" "etcd_backup" {
  bucket        = local.etcd_backup_bucket_name
  force_destroy = false

  tags = merge(var.tags, {
    Name    = local.etcd_backup_bucket_name
    Purpose = "k3s-etcd-snapshots"
  })
}

resource "aws_s3_bucket_versioning" "etcd_backup" {
  bucket = aws_s3_bucket.etcd_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "etcd_backup" {
  bucket = aws_s3_bucket.etcd_backup.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "etcd_backup" {
  bucket                  = aws_s3_bucket.etcd_backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "etcd_backup" {
  bucket = aws_s3_bucket.etcd_backup.id

  rule {
    id     = "etcd-snapshot-retention"
    status = "Enabled"

    filter {}

    # Move to cheaper storage after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Delete after 60 days — keep rolling 60-day window
    expiration {
      days = 60
    }

    # Clean up incomplete multipart uploads
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# Block any accidental public bucket policy
resource "aws_s3_bucket_policy" "etcd_backup" {
  bucket = aws_s3_bucket.etcd_backup.id
  policy = data.aws_iam_policy_document.etcd_backup_bucket_policy.json

  depends_on = [aws_s3_bucket_public_access_block.etcd_backup]
}

data "aws_iam_policy_document" "etcd_backup_bucket_policy" {
  # Deny any non-SSL requests
  statement {
    sid     = "DenyNonSSL"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.etcd_backup.arn,
      "${aws_s3_bucket.etcd_backup.arn}/*"
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Allow access only from k3s server role
  statement {
    sid     = "AllowK3sServerRole"
    effect  = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      aws_s3_bucket.etcd_backup.arn,
      "${aws_s3_bucket.etcd_backup.arn}/*"
    ]
    principals {
      type        = "AWS"
      identifiers = [var.k3s_server_role_arn]
    }
  }
}

# =============================================================================
# 2. VELERO BACKUP BUCKET
# =============================================================================

resource "aws_s3_bucket" "velero_backup" {
  bucket        = local.velero_backup_bucket_name
  force_destroy = false

  tags = merge(var.tags, {
    Name    = local.velero_backup_bucket_name
    Purpose = "velero-cluster-backups"
  })
}

resource "aws_s3_bucket_versioning" "velero_backup" {
  bucket = aws_s3_bucket.velero_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero_backup" {
  bucket = aws_s3_bucket.velero_backup.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "velero_backup" {
  bucket                  = aws_s3_bucket.velero_backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "velero_backup" {
  bucket = aws_s3_bucket.velero_backup.id

  rule {
    id     = "velero-backup-retention"
    status = "Enabled"

    filter {}

    # Move to STANDARD_IA after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Move to Glacier after 60 days
    transition {
      days          = 60
      storage_class = "GLACIER"
    }

    # Delete after 90 days
    expiration {
      days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 14
    }
  }
}

resource "aws_s3_bucket_policy" "velero_backup" {
  bucket = aws_s3_bucket.velero_backup.id
  policy = data.aws_iam_policy_document.velero_backup_bucket_policy.json

  depends_on = [aws_s3_bucket_public_access_block.velero_backup]
}

data "aws_iam_policy_document" "velero_backup_bucket_policy" {
  statement {
    sid     = "DenyNonSSL"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.velero_backup.arn,
      "${aws_s3_bucket.velero_backup.arn}/*"
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid     = "AllowK3sWorkerRole"
    effect  = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload"
    ]
    resources = [
      aws_s3_bucket.velero_backup.arn,
      "${aws_s3_bucket.velero_backup.arn}/*"
    ]
    principals {
      type        = "AWS"
      identifiers = [var.k3s_worker_role_arn]
    }
  }
}

# =============================================================================
# 3. LONGHORN BACKUP BUCKET
# =============================================================================

resource "aws_s3_bucket" "longhorn_backup" {
  bucket        = local.longhorn_backup_bucket_name
  force_destroy = false

  tags = merge(var.tags, {
    Name    = local.longhorn_backup_bucket_name
    Purpose = "longhorn-volume-backups"
  })
}

resource "aws_s3_bucket_versioning" "longhorn_backup" {
  bucket = aws_s3_bucket.longhorn_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "longhorn_backup" {
  bucket = aws_s3_bucket.longhorn_backup.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "longhorn_backup" {
  bucket                  = aws_s3_bucket.longhorn_backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "longhorn_backup" {
  bucket = aws_s3_bucket.longhorn_backup.id

  rule {
    id     = "longhorn-backup-retention"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 60
      storage_class = "GLACIER"
    }

    expiration {
      days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  rule {
    id     = "delete-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 14
    }
  }
}

resource "aws_s3_bucket_policy" "longhorn_backup" {
  bucket = aws_s3_bucket.longhorn_backup.id
  policy = data.aws_iam_policy_document.longhorn_backup_bucket_policy.json

  depends_on = [aws_s3_bucket_public_access_block.longhorn_backup]
}

data "aws_iam_policy_document" "longhorn_backup_bucket_policy" {
  statement {
    sid     = "DenyNonSSL"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.longhorn_backup.arn,
      "${aws_s3_bucket.longhorn_backup.arn}/*"
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid     = "AllowK3sWorkerRole"
    effect  = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload"
    ]
    resources = [
      aws_s3_bucket.longhorn_backup.arn,
      "${aws_s3_bucket.longhorn_backup.arn}/*"
    ]
    principals {
      type        = "AWS"
      identifiers = [var.k3s_worker_role_arn]
    }
  }
}

# =============================================================================
# S3 GATEWAY ENDPOINT — FREE, keeps S3 traffic inside AWS network
# Attached to private route tables so nodes use it automatically
# =============================================================================

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids

  policy = data.aws_iam_policy_document.s3_endpoint_policy.json

  tags = merge(var.tags, {
    Name    = "${var.cluster_name}-s3-gateway-endpoint"
    Purpose = "free-s3-private-routing"
  })
}

# Restrict endpoint to only allow access to your buckets
# Prevents using this endpoint to access other AWS accounts' S3
data "aws_iam_policy_document" "s3_endpoint_policy" {
  statement {
    sid    = "AllowClusterBuckets"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload"
    ]
    resources = [
      aws_s3_bucket.etcd_backup.arn,
      "${aws_s3_bucket.etcd_backup.arn}/*",
      aws_s3_bucket.velero_backup.arn,
      "${aws_s3_bucket.velero_backup.arn}/*",
      aws_s3_bucket.longhorn_backup.arn,
      "${aws_s3_bucket.longhorn_backup.arn}/*"
    ]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }
}