output "vpc_id" {
  description = "VPC ID"
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Map of AZ to public subnet ID"
  value = {
      for az, subnet in aws_subnet.public : az => subnet.id
  }
}

output "private_subnet_ids" {
  description = "Map of AZ to private subnet ID"
  value = {
      for az, subnet in aws_subnet.private : az => subnet.id
  }
}

output "nat_gateway_ids" {
  description = "Map of AZ to NAT Gateway ID"
  value       = {
    for az, nat in aws_nat_gateway.main : az => nat.id
  }
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.main.id
}

output "private_route_table_ids" {
  description = "List of private route table IDs (for S3/VPC gateway endpoints)"
  value       = [for rt in aws_route_table.private : rt.id]
}
