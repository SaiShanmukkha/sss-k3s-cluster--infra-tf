terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

/* VPC */
resource "aws_vpc" "main" {
    cidr_block = var.vpc_cidr
    enable_dns_support = true
    enable_dns_hostnames = true
    
    tags = merge(var.tags,{
        Name = "${var.cluster_name}-vpc"
    }
  )
}


/* Public Subnets - One per AZ */
resource "aws_subnet" "public" {
    for_each = var.public_subnet_cidrs
  
    vpc_id = aws_vpc.main.id
    cidr_block = each.value
    availability_zone = each.key
    map_public_ip_on_launch = true

    tags = merge(var.tags,{
        Name = "${var.cluster_name}-public-${each.key}"
        AZ = each.key
        Tier = "public"
    })
}



/* Private Subnets - One per AZ */
resource "aws_subnet" "private" {
    for_each = var.private_subnet_cidrs

    vpc_id = aws_vpc.main.id
    cidr_block = each.value
    availability_zone = each.key
    map_public_ip_on_launch = false

    tags = merge(var.tags,{
        Name = "${var.cluster_name}-private-${each.key}"
        AZ = each.key
        Tier = "private"
    })
}


/* Internet Gateway */
resource "aws_internet_gateway" "main" {
    vpc_id = aws_vpc.main.id

    tags = merge(var.tags,{
        Name = "${var.cluster_name}-igw"
    })
}



/* Elastic IP for NAT Gateway */
resource "aws_eip" "nat" {
    for_each = var.enable_nat_gateway ? var.public_nat_subnet_cidrs : toset([])
    domain = "vpc"
    tags = merge(var.tags,{
        Name = "${var.cluster_name}-nat-eip-${each.key}"
        AZ   = each.key
    })

    depends_on = [ aws_internet_gateway.main ]
}


/* NAT Gateway - Only if enabled */
resource "aws_nat_gateway" "main" {
    for_each = var.enable_nat_gateway ? var.public_nat_subnet_cidrs : toset([])

    allocation_id = aws_eip.nat[each.key].id
    subnet_id     = aws_subnet.public[each.key].id

    tags = merge(var.tags,{
        Name = "${var.cluster_name}-nat-${each.key}"
        AZ   = each.key
    })

    depends_on = [ aws_eip.nat ]
}

/* Route Table for Public Subnets */
resource "aws_route_table" "public" {
    vpc_id = aws_vpc.main.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.main.id
    }

    tags = merge(var.tags,{
        Name = "${var.cluster_name}-public-rt"
    })
}

resource "aws_route_table_association" "public" {
    for_each = aws_subnet.public

    subnet_id = each.value.id
    route_table_id = aws_route_table.public.id
}


/* Route Table for Private Subnets */
resource "aws_route_table" "private" {
    for_each = var.private_subnet_cidrs

    vpc_id = aws_vpc.main.id

    tags = merge(var.tags,{
        Name = "${var.cluster_name}-private-rt-${each.key}"
    })
}

resource "aws_route" "private_net" {
    for_each = var.enable_nat_gateway ? var.private_subnet_cidrs : {}

    route_table_id         = aws_route_table.private[each.key].id
    destination_cidr_block = "0.0.0.0/0"
    nat_gateway_id         = aws_nat_gateway.main[
        contains(var.public_nat_subnet_cidrs, each.key) ? each.key : tolist(var.public_nat_subnet_cidrs)[0]
    ].id
}

resource "aws_route_table_association" "private" {
    for_each = aws_subnet.private

    subnet_id = each.value.id
    route_table_id = aws_route_table.private[each.key].id
}