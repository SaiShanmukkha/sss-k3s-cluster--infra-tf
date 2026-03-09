output "bastion_public_ip" {
  description = "Bastion Elastic IP — use this for SSH"
  value       = aws_eip.bastion.public_ip
}

output "bastion_private_ip" {
  description = "Bastion private IP"
  value       = aws_instance.bastion.private_ip
}

output "bastion_instance_id" {
  description = "Bastion EC2 instance ID"
  value       = aws_instance.bastion.id
}

output "bastion_ami_id" {
  description = "Rocky Linux 9 AMI used"
  value       = data.aws_ami.rocky9.id
}