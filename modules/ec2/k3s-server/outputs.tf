output "server_instance_id" {
  value = aws_instance.k3s_server.id
}

output "server_private_ip" {
  value = aws_instance.k3s_server.private_ip
}

output "server_ami_id" {
  value = data.aws_ami.rocky9.id
}