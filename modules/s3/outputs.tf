output "etcd_backup_bucket_name" {
  value = aws_s3_bucket.etcd_backup.id
}

output "etcd_backup_bucket_arn" {
  value = aws_s3_bucket.etcd_backup.arn
}

output "velero_backup_bucket_name" {
  value = aws_s3_bucket.velero_backup.id
}

output "velero_backup_bucket_arn" {
  value = aws_s3_bucket.velero_backup.arn
}

output "longhorn_backup_bucket_name" {
  value = aws_s3_bucket.longhorn_backup.id
}

output "longhorn_backup_bucket_arn" {
  value = aws_s3_bucket.longhorn_backup.arn
}

output "s3_gateway_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}