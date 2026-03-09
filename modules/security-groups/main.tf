# =============================================================================
# modules/security-groups/main.tf
# 4 Security Groups:
#   1. sg-bastion      → SSH jump host
#   2. sg-ingress      → HAProxy nodes (public)
#   3. sg-k3s-server   → Control plane nodes (private)
#   4. sg-k3s-worker   → Worker nodes (private)
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# =============================================================================
# 1. BASTION SG
# =============================================================================

resource "aws_security_group" "bastion" {
  name        = "${var.cluster_name}-sg-bastion"
  description = "SSH jump host - inbound SSH from office IP only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-sg-bastion"
    Role = "bastion"
  })
}

# Inbound SSH from office IP only
resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  security_group_id = aws_security_group.bastion.id
  description       = "SSH from bastion_allowed_cidr"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.bastion_allowed_cidr
}

# Outbound SSH to internal nodes
resource "aws_vpc_security_group_egress_rule" "bastion_to_servers" {
  security_group_id            = aws_security_group.bastion.id
  description                  = "SSH to k3s server nodes"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.k3s_server.id
}

resource "aws_vpc_security_group_egress_rule" "bastion_to_workers" {
  security_group_id            = aws_security_group.bastion.id
  description                  = "SSH to k3s worker nodes"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.k3s_worker.id
}

resource "aws_vpc_security_group_egress_rule" "bastion_to_ingress" {
  security_group_id            = aws_security_group.bastion.id
  description                  = "SSH to ingress nodes"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.ingress.id
}

# Outbound kubectl to k3s server API
resource "aws_vpc_security_group_egress_rule" "bastion_to_server_api" {
  security_group_id            = aws_security_group.bastion.id
  description                  = "kubectl API access to k3s server nodes"
  ip_protocol                  = "tcp"
  from_port                    = 6443
  to_port                      = 6443
  referenced_security_group_id = aws_security_group.k3s_server.id
}

# Outbound HTTPS for package updates on bastion itself
resource "aws_vpc_security_group_egress_rule" "bastion_https" {
  security_group_id = aws_security_group.bastion.id
  description       = "HTTPS outbound for apt updates"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "bastion_http" {
  security_group_id = aws_security_group.bastion.id
  description       = "HTTP outbound for apt updates"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "bastion_dns_udp" {
  security_group_id = aws_security_group.bastion.id
  description       = "DNS UDP outbound"
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "bastion_dns_tcp" {
  security_group_id = aws_security_group.bastion.id
  description       = "DNS TCP outbound"
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = "0.0.0.0/0"
}

# =============================================================================
# 2. INGRESS SG — HAProxy nodes (public subnet)
# =============================================================================

resource "aws_security_group" "ingress" {
  name        = "${var.cluster_name}-sg-ingress"
  description = "HAProxy ingress nodes - public HTTP/HTTPS + Keepalived"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-sg-ingress"
    Role = "ingress"
  })
}

# Inbound HTTP from internet
resource "aws_vpc_security_group_ingress_rule" "ingress_http" {
  security_group_id = aws_security_group.ingress.id
  description       = "HTTP from internet"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# Inbound HTTPS from internet
resource "aws_vpc_security_group_ingress_rule" "ingress_https" {
  security_group_id = aws_security_group.ingress.id
  description       = "HTTPS from internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# Inbound kubectl from bastion_allowed_cidr (direct API server access)
resource "aws_vpc_security_group_ingress_rule" "ingress_kubectl" {
  security_group_id = aws_security_group.ingress.id
  description       = "kubectl API access from bastion_allowed_cidr"
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
  cidr_ipv4         = var.bastion_allowed_cidr
}

# Inbound SSH from bastion only
resource "aws_vpc_security_group_ingress_rule" "ingress_ssh" {
  security_group_id            = aws_security_group.ingress.id
  description                  = "SSH from bastion only"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.bastion.id
}

# Inbound VRRP from other ingress node (Keepalived)
resource "aws_vpc_security_group_ingress_rule" "ingress_vrrp" {
  security_group_id            = aws_security_group.ingress.id
  description                  = "VRRP for Keepalived between ingress nodes"
  ip_protocol                  = "112"
  referenced_security_group_id = aws_security_group.ingress.id
}

# Outbound to workers — Traefik HTTP NodePort
resource "aws_vpc_security_group_egress_rule" "ingress_to_worker_http" {
  security_group_id            = aws_security_group.ingress.id
  description                  = "HAProxy to Traefik HTTP NodePort on workers"
  ip_protocol                  = "tcp"
  from_port                    = 30080
  to_port                      = 30080
  referenced_security_group_id = aws_security_group.k3s_worker.id
}

# Outbound to workers — Traefik HTTPS NodePort
resource "aws_vpc_security_group_egress_rule" "ingress_to_worker_https" {
  security_group_id            = aws_security_group.ingress.id
  description                  = "HAProxy to Traefik HTTPS NodePort on workers"
  ip_protocol                  = "tcp"
  from_port                    = 30443
  to_port                      = 30443
  referenced_security_group_id = aws_security_group.k3s_worker.id
}

# Outbound to servers — kubectl API proxy
resource "aws_vpc_security_group_egress_rule" "ingress_to_server_api" {
  security_group_id            = aws_security_group.ingress.id
  description                  = "HAProxy to k3s API server"
  ip_protocol                  = "tcp"
  from_port                    = 6443
  to_port                      = 6443
  referenced_security_group_id = aws_security_group.k3s_server.id
}

# Outbound VRRP to other ingress node (Keepalived advertisements)
resource "aws_vpc_security_group_egress_rule" "ingress_vrrp_out" {
  security_group_id            = aws_security_group.ingress.id
  description                  = "VRRP outbound for Keepalived advertisements"
  ip_protocol                  = "112"
  referenced_security_group_id = aws_security_group.ingress.id
}

# Outbound HTTPS for apt updates on ingress nodes
resource "aws_vpc_security_group_egress_rule" "ingress_https_out" {
  security_group_id = aws_security_group.ingress.id
  description       = "HTTPS outbound via NAT for apt updates"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "ingress_http_out" {
  security_group_id = aws_security_group.ingress.id
  description       = "HTTP outbound via NAT for apt updates"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "ingress_dns_udp" {
  security_group_id = aws_security_group.ingress.id
  description       = "DNS UDP outbound"
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "ingress_dns_tcp" {
  security_group_id = aws_security_group.ingress.id
  description       = "DNS TCP outbound"
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = "0.0.0.0/0"
}

# =============================================================================
# 3. K3S SERVER SG — Control plane nodes (private subnet)
# =============================================================================

resource "aws_security_group" "k3s_server" {
  name        = "${var.cluster_name}-sg-k3s-server"
  description = "k3s control plane nodes - API server, etcd, kubelet"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-sg-k3s-server"
    Role = "k3s-server"
  })
}

# Inbound SSH from bastion
resource "aws_vpc_security_group_ingress_rule" "server_ssh" {
  security_group_id            = aws_security_group.k3s_server.id
  description                  = "SSH from bastion only"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.bastion.id
}

# Inbound API server from bastion (kubectl from jump host)
resource "aws_vpc_security_group_ingress_rule" "server_api_from_bastion" {
  security_group_id            = aws_security_group.k3s_server.id
  description                  = "k3s API from bastion (kubectl)"
  ip_protocol                  = "tcp"
  from_port                    = 6443
  to_port                      = 6443
  referenced_security_group_id = aws_security_group.bastion.id
}

# Inbound API server from ingress (HAProxy proxies kubectl)
resource "aws_vpc_security_group_ingress_rule" "server_api_from_ingress" {
  security_group_id            = aws_security_group.k3s_server.id
  description                  = "k3s API from HAProxy ingress"
  ip_protocol                  = "tcp"
  from_port                    = 6443
  to_port                      = 6443
  referenced_security_group_id = aws_security_group.ingress.id
}

# Inbound API server from workers (workers register with API server)
resource "aws_vpc_security_group_ingress_rule" "server_api_from_workers" {
  security_group_id            = aws_security_group.k3s_server.id
  description                  = "k3s API from worker nodes"
  ip_protocol                  = "tcp"
  from_port                    = 6443
  to_port                      = 6443
  referenced_security_group_id = aws_security_group.k3s_worker.id
}

# Inbound API server from other servers (HA control plane comms)
resource "aws_vpc_security_group_ingress_rule" "server_api_from_servers" {
  security_group_id            = aws_security_group.k3s_server.id
  description                  = "k3s API server-to-server (HA)"
  ip_protocol                  = "tcp"
  from_port                    = 6443
  to_port                      = 6443
  referenced_security_group_id = aws_security_group.k3s_server.id
}

# Inbound etcd client — server to server only
resource "aws_vpc_security_group_ingress_rule" "server_etcd_client" {
  security_group_id            = aws_security_group.k3s_server.id
  description                  = "etcd client port - server to server only"
  ip_protocol                  = "tcp"
  from_port                    = 2379
  to_port                      = 2379
  referenced_security_group_id = aws_security_group.k3s_server.id
}

# Inbound etcd peer — server to server only
resource "aws_vpc_security_group_ingress_rule" "server_etcd_peer" {
  security_group_id            = aws_security_group.k3s_server.id
  description                  = "etcd peer port - server to server only"
  ip_protocol                  = "tcp"
  from_port                    = 2380
  to_port                      = 2380
  referenced_security_group_id = aws_security_group.k3s_server.id
}

# Inbound kubelet from servers
resource "aws_vpc_security_group_ingress_rule" "server_kubelet_from_servers" {
  security_group_id            = aws_security_group.k3s_server.id
  description                  = "kubelet from other server nodes"
  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250
  referenced_security_group_id = aws_security_group.k3s_server.id
}

# Inbound kubelet from workers
resource "aws_vpc_security_group_ingress_rule" "server_kubelet_from_workers" {
  security_group_id            = aws_security_group.k3s_server.id
  description                  = "kubelet health checks from workers"
  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250
  referenced_security_group_id = aws_security_group.k3s_worker.id
}

# Inbound node-exporter from workers (Prometheus on workers scrapes node-exporter on servers)
resource "aws_vpc_security_group_ingress_rule" "server_nodeexporter_from_workers" {
  security_group_id            = aws_security_group.k3s_server.id
  description                  = "Prometheus node-exporter scrape from workers"
  ip_protocol                  = "tcp"
  from_port                    = 9100
  to_port                      = 9100
  referenced_security_group_id = aws_security_group.k3s_worker.id
}

# Inbound Flannel VXLAN from servers
resource "aws_vpc_security_group_ingress_rule" "server_flannel_from_servers" {
  security_group_id            = aws_security_group.k3s_server.id
  description                  = "Flannel VXLAN overlay from servers"
  ip_protocol                  = "udp"
  from_port                    = 8472
  to_port                      = 8472
  referenced_security_group_id = aws_security_group.k3s_server.id
}

# Inbound Flannel VXLAN from workers
resource "aws_vpc_security_group_ingress_rule" "server_flannel_from_workers" {
  security_group_id            = aws_security_group.k3s_server.id
  description                  = "Flannel VXLAN overlay from workers"
  ip_protocol                  = "udp"
  from_port                    = 8472
  to_port                      = 8472
  referenced_security_group_id = aws_security_group.k3s_worker.id
}

# Outbound — all to workers (control plane manages workers)
resource "aws_vpc_security_group_egress_rule" "server_to_workers_all" {
  security_group_id            = aws_security_group.k3s_server.id
  description                  = "Control plane to workers (kubelet, flannel)"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.k3s_worker.id
}

# Outbound — all to other servers (etcd, API)
resource "aws_vpc_security_group_egress_rule" "server_to_servers_all" {
  security_group_id            = aws_security_group.k3s_server.id
  description                  = "Server to server (etcd peer, API)"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.k3s_server.id
}

# Outbound HTTPS — DockerHub, apt, Helm, Let's Encrypt via NAT
resource "aws_vpc_security_group_egress_rule" "server_https_out" {
  security_group_id = aws_security_group.k3s_server.id
  description       = "HTTPS outbound via NAT instance"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "server_http_out" {
  security_group_id = aws_security_group.k3s_server.id
  description       = "HTTP outbound via NAT instance"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# Outbound DNS — needed for all name resolution
resource "aws_vpc_security_group_egress_rule" "server_dns_udp" {
  security_group_id = aws_security_group.k3s_server.id
  description       = "DNS UDP outbound"
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "server_dns_tcp" {
  security_group_id = aws_security_group.k3s_server.id
  description       = "DNS TCP outbound"
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = "0.0.0.0/0"
}

# =============================================================================
# 4. K3S WORKER SG — Worker nodes (private subnet)
# =============================================================================

resource "aws_security_group" "k3s_worker" {
  name        = "${var.cluster_name}-sg-k3s-worker"
  description = "k3s worker nodes - workloads, Longhorn, Traefik NodePort"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-sg-k3s-worker"
    Role = "k3s-worker"
  })
}

# Inbound SSH from bastion
resource "aws_vpc_security_group_ingress_rule" "worker_ssh" {
  security_group_id            = aws_security_group.k3s_worker.id
  description                  = "SSH from bastion only"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.bastion.id
}

# Inbound Traefik HTTP NodePort from ingress (HAProxy)
resource "aws_vpc_security_group_ingress_rule" "worker_nodeport_http" {
  security_group_id            = aws_security_group.k3s_worker.id
  description                  = "Traefik HTTP NodePort from HAProxy"
  ip_protocol                  = "tcp"
  from_port                    = 30080
  to_port                      = 30080
  referenced_security_group_id = aws_security_group.ingress.id
}

# Inbound Traefik HTTPS NodePort from ingress (HAProxy)
resource "aws_vpc_security_group_ingress_rule" "worker_nodeport_https" {
  security_group_id            = aws_security_group.k3s_worker.id
  description                  = "Traefik HTTPS NodePort from HAProxy"
  ip_protocol                  = "tcp"
  from_port                    = 30443
  to_port                      = 30443
  referenced_security_group_id = aws_security_group.ingress.id
}

# Inbound kubelet from control plane
resource "aws_vpc_security_group_ingress_rule" "worker_kubelet" {
  security_group_id            = aws_security_group.k3s_worker.id
  description                  = "kubelet from control plane"
  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250
  referenced_security_group_id = aws_security_group.k3s_server.id
}

# Inbound Flannel VXLAN from servers
resource "aws_vpc_security_group_ingress_rule" "worker_flannel_from_servers" {
  security_group_id            = aws_security_group.k3s_worker.id
  description                  = "Flannel VXLAN from servers"
  ip_protocol                  = "udp"
  from_port                    = 8472
  to_port                      = 8472
  referenced_security_group_id = aws_security_group.k3s_server.id
}

# Inbound Flannel VXLAN from workers (pod-to-pod across nodes)
resource "aws_vpc_security_group_ingress_rule" "worker_flannel_from_workers" {
  security_group_id            = aws_security_group.k3s_worker.id
  description                  = "Flannel VXLAN from other workers"
  ip_protocol                  = "udp"
  from_port                    = 8472
  to_port                      = 8472
  referenced_security_group_id = aws_security_group.k3s_worker.id
}

# Inbound Longhorn manager from workers
resource "aws_vpc_security_group_ingress_rule" "worker_longhorn_manager" {
  security_group_id            = aws_security_group.k3s_worker.id
  description                  = "Longhorn manager port"
  ip_protocol                  = "tcp"
  from_port                    = 9500
  to_port                      = 9500
  referenced_security_group_id = aws_security_group.k3s_worker.id
}

# Inbound Longhorn replica sync from workers
resource "aws_vpc_security_group_ingress_rule" "worker_longhorn_replica" {
  security_group_id            = aws_security_group.k3s_worker.id
  description                  = "Longhorn replica sync between workers"
  ip_protocol                  = "tcp"
  from_port                    = 9501
  to_port                      = 9503
  referenced_security_group_id = aws_security_group.k3s_worker.id
}

# Inbound pod-to-pod all traffic within worker SG (same cluster)
resource "aws_vpc_security_group_ingress_rule" "worker_pod_to_pod" {
  security_group_id            = aws_security_group.k3s_worker.id
  description                  = "Pod to pod traffic across worker nodes"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.k3s_worker.id
}

# Outbound to API server
resource "aws_vpc_security_group_egress_rule" "worker_to_api" {
  security_group_id            = aws_security_group.k3s_worker.id
  description                  = "Worker to k3s API server"
  ip_protocol                  = "tcp"
  from_port                    = 6443
  to_port                      = 6443
  referenced_security_group_id = aws_security_group.k3s_server.id
}

# Outbound Flannel VXLAN to servers (pod-to-pod overlay: worker pods → server pods, including CoreDNS)
resource "aws_vpc_security_group_egress_rule" "worker_flannel_to_servers" {
  security_group_id            = aws_security_group.k3s_worker.id
  description                  = "Flannel VXLAN from workers to server nodes"
  ip_protocol                  = "udp"
  from_port                    = 8472
  to_port                      = 8472
  referenced_security_group_id = aws_security_group.k3s_server.id
}

# Outbound kubelet to servers (Prometheus scrapes kubelet on server nodes directly)
resource "aws_vpc_security_group_egress_rule" "worker_to_server_kubelet" {
  security_group_id            = aws_security_group.k3s_worker.id
  description                  = "Prometheus kubelet scrape on server nodes"
  ip_protocol                  = "tcp"
  from_port                    = 10250
  to_port                      = 10250
  referenced_security_group_id = aws_security_group.k3s_server.id
}

# Outbound node-exporter to servers (Prometheus scrapes node-exporter on server nodes)
resource "aws_vpc_security_group_egress_rule" "worker_to_server_nodeexporter" {
  security_group_id            = aws_security_group.k3s_worker.id
  description                  = "Prometheus node-exporter scrape on server nodes"
  ip_protocol                  = "tcp"
  from_port                    = 9100
  to_port                      = 9100
  referenced_security_group_id = aws_security_group.k3s_server.id
}

# Outbound all to other workers (pod-to-pod, Longhorn)
resource "aws_vpc_security_group_egress_rule" "worker_to_workers_all" {
  security_group_id            = aws_security_group.k3s_worker.id
  description                  = "Worker to worker (pods, Longhorn replication)"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.k3s_worker.id
}

# Outbound HTTPS via NAT — DockerHub, apt, Helm
resource "aws_vpc_security_group_egress_rule" "worker_https_out" {
  security_group_id = aws_security_group.k3s_worker.id
  description       = "HTTPS outbound via NAT instance"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "worker_http_out" {
  security_group_id = aws_security_group.k3s_worker.id
  description       = "HTTP outbound via NAT instance"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# Outbound DNS
resource "aws_vpc_security_group_egress_rule" "worker_dns_udp" {
  security_group_id = aws_security_group.k3s_worker.id
  description       = "DNS UDP"
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "worker_dns_tcp" {
  security_group_id = aws_security_group.k3s_worker.id
  description       = "DNS TCP"
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = "0.0.0.0/0"
}
