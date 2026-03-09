output "bastion_sg_id" {
  description = "Security group ID for bastion host"
  value       = aws_security_group.bastion.id
}

output "ingress_sg_id" {
  description = "Security group ID for HAProxy ingress nodes"
  value       = aws_security_group.ingress.id
}

output "k3s_server_sg_id" {
  description = "Security group ID for k3s server nodes"
  value       = aws_security_group.k3s_server.id
}

output "k3s_worker_sg_id" {
  description = "Security group ID for k3s worker nodes"
  value       = aws_security_group.k3s_worker.id
}

