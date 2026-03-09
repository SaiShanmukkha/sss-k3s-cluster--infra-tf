output "ingress_eip" {
  description = "Floating EIP — point your DNS wildcard here"
  value       = aws_eip.ingress.public_ip
}

output "ingress_eip_allocation_id" {
  value = aws_eip.ingress.allocation_id
}

output "ingress_1_instance_id" {
  value = aws_instance.ingress_1.id
}

output "ingress_2_instance_id" {
  value = aws_instance.ingress_2.id
}

output "ingress_1_private_ip" {
  value = aws_instance.ingress_1.private_ip
}

output "ingress_2_private_ip" {
  value = aws_instance.ingress_2.private_ip
}

output "ingress_1_public_ip" {
  value = aws_instance.ingress_1.public_ip
}

output "ingress_2_public_ip" {
  value = aws_instance.ingress_2.public_ip
}