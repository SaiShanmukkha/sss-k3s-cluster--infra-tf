output "admin_key_name" {
  description = "AWS key pair name for bastion"
  value       = aws_key_pair.admin.key_name
}

output "admin_key_id" {
  description = "AWS key pair ID for bastion"
  value       = aws_key_pair.admin.id
}

output "internal_key_name" {
  description = "AWS key pair name for servers, workers, ingress"
  value       = aws_key_pair.internal.key_name
}

output "internal_key_id" {
  description = "AWS key pair ID for internal nodes"
  value       = aws_key_pair.internal.id
}

# output "admin_ssm_path" {
#   description = "SSM path to retrieve admin private key"
#   value       = aws_ssm_parameter.admin_private_key.name
# }

# output "internal_ssm_path" {
#   description = "SSM path to retrieve internal private key"
#   value       = aws_ssm_parameter.internal_private_key.name
# }

output "admin_private_key_pem" {
  value     = tls_private_key.admin.private_key_pem
  sensitive = true
}

output "internal_private_key_pem" {
  value     = tls_private_key.internal.private_key_pem
  sensitive = true
}