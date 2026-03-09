#!/bin/bash
set -euo pipefail

hostnamectl set-hostname ${cluster_name}-ingress-${node_index}

# Update system
dnf update -y
dnf install -y haproxy keepalived curl wget unzip

# Install AWS CLI v2 (required for EIP failover script)
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws

# Harden SSH
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
systemctl restart sshd

# ─── HAProxy Configuration ───────────────────────────────────────────────────
cat > /etc/haproxy/haproxy.cfg << 'HAPROXY'
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon
    maxconn 50000

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5s
    timeout client  50s
    timeout server  50s

# ── Stats page (internal only) ───────────────────────────────────────────────
frontend stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats auth admin:${haproxy_stats_password}
    stats admin if { src 127.0.0.1 }

# ── HTTP → Workers (Traefik HTTP NodePort) ───────────────────────────────────
frontend http_in
    bind *:80
    mode tcp
    default_backend traefik_http

backend traefik_http
    mode tcp
    balance roundrobin
    option tcp-check
HAPROXY

# Dynamically add worker backends for HTTP
IFS=',' read -ra WORKERS <<< "${worker_ips}"
for ip in "$${WORKERS[@]}"; do
  echo "    server worker-$ip $ip:${traefik_http_port} check" >> /etc/haproxy/haproxy.cfg
done

cat >> /etc/haproxy/haproxy.cfg << 'HAPROXY'

# ── HTTPS → Workers (Traefik HTTPS NodePort) ─────────────────────────────────
frontend https_in
    bind *:443
    mode tcp
    default_backend traefik_https

backend traefik_https
    mode tcp
    balance roundrobin
    option tcp-check
HAPROXY

for ip in "$${WORKERS[@]}"; do
  echo "    server worker-$ip $ip:${traefik_https_port} check" >> /etc/haproxy/haproxy.cfg
done

cat >> /etc/haproxy/haproxy.cfg << 'HAPROXY'

# ── k3s API Server ────────────────────────────────────────────────────────────
frontend k3s_api
    bind *:6443
    mode tcp
    default_backend k3s_servers

backend k3s_servers
    mode tcp
    balance roundrobin
    option tcp-check
HAPROXY

IFS=',' read -ra SERVERS <<< "${k3s_server_ips}"
for ip in "$${SERVERS[@]}"; do
  echo "    server server-$ip $ip:6443 check" >> /etc/haproxy/haproxy.cfg
done

# Enable and start HAProxy
systemctl enable haproxy
systemctl start haproxy

# ─── Keepalived Configuration ─────────────────────────────────────────────────
# Get instance token for AWS API calls (IMDSv2)
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s "http://169.254.169.254/latest/meta-data/instance-id" \
  -H "X-aws-ec2-metadata-token: $TOKEN")
REGION=$(curl -s "http://169.254.169.254/latest/meta-data/placement/region" \
  -H "X-aws-ec2-metadata-token: $TOKEN")

# Keepalived notify script — reassociates EIP on failover
cat > /etc/keepalived/failover.sh << FAILOVER
#!/bin/bash
# Called by Keepalived on state change
# When this node becomes MASTER → associate EIP to this instance
STATE=\$1
if [ "\$STATE" = "MASTER" ]; then
  aws ec2 associate-address \
    --instance-id $INSTANCE_ID \
    --allocation-id ${eip_allocation_id} \
    --allow-reassociation \
    --region $REGION
  logger "Keepalived: EIP ${eip_allocation_id} associated to $INSTANCE_ID"
fi
FAILOVER
chmod +x /etc/keepalived/failover.sh

cat > /etc/keepalived/keepalived.conf << KEEPALIVED
global_defs {
   router_id ${cluster_name}-ingress-${node_index}
   script_user root
   enable_script_security
}

vrrp_script check_haproxy {
    script "/usr/bin/pgrep haproxy"
    interval 2
    weight   -20
    fall     2
    rise     2
}

vrrp_instance VI_1 {
    state ${keepalived_role}
    interface eth0
    virtual_router_id 51
    priority ${keepalived_priority}
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass ${keepalived_auth_pass}
    }

    unicast_src_ip $(hostname -I | awk '{print $1}')
    unicast_peer {
        ${peer_ip}
    }

    track_script {
        check_haproxy
    }

    notify /etc/keepalived/failover.sh
}
KEEPALIVED

systemctl enable keepalived
systemctl start keepalived

echo "Ingress node ${node_index} setup complete" >> /var/log/userdata.log