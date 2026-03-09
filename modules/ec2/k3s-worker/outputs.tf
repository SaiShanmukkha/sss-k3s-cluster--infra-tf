output "worker_instance_ids" {
  description = "Spot instance request IDs"
  value = {
    for k, v in aws_spot_instance_request.k3s_worker :
    k => v.spot_instance_id
  }
}

output "worker_private_ips" {
  value = {
    for k, v in aws_spot_instance_request.k3s_worker :
    k => v.private_ip
  }
}

output "longhorn_volume_ids" {
  value = {
    for k, v in aws_ebs_volume.longhorn :
    k => v.id
  }
}