output "k3s_server_instance_profile_name" {
  value = aws_iam_instance_profile.k3s_server.name
}

output "k3s_worker_instance_profile_name" {
  value = aws_iam_instance_profile.k3s_worker.name
}

output "ingress_instance_profile_name" {
  value = aws_iam_instance_profile.ingress.name
}

output "bastion_instance_profile_name" {
  value = aws_iam_instance_profile.bastion.name
}

output "k3s_server_role_arn" {
  value = aws_iam_role.k3s_server.arn
}

output "k3s_worker_role_arn" {
  value = aws_iam_role.k3s_worker.arn
}

output "ingress_role_arn" {
  value = aws_iam_role.ingress.arn
}

output "bastion_role_arn" {
  value = aws_iam_role.bastion.arn
}

output "ssm_session_manager_policy_arn" {
  value = aws_iam_policy.ssm_session_manager.arn
}

# =============================================================================
# Longhorn IAM user credentials (for the longhorn-s3-secret k8s Secret)
# =============================================================================

output "longhorn_s3_access_key_id" {
  description = "Longhorn IAM user access key ID for S3 backup"
  value       = aws_iam_access_key.longhorn_s3.id
  sensitive   = true
}

output "longhorn_s3_secret_access_key" {
  description = "Longhorn IAM user secret access key for S3 backup"
  value       = aws_iam_access_key.longhorn_s3.secret
  sensitive   = true
}