#!/bin/bash
set -euo pipefail

hostnamectl set-hostname ${cluster_name}-${node_name}

# ─── System prep ─────────────────────────────────────────────────────────────
dnf update -y
dnf install -y epel-release
dnf install -y curl wget git vim htop iptables-services container-selinux

# Longhorn dependencies
dnf install -y iscsi-initiator-utils nfs-utils cryptsetup
systemctl enable --now iscsid

# Disable swap (required for k3s)
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Load required kernel modules
modprobe overlay
modprobe br_netfilter
modprobe nfs
modprobe dm_crypt

cat > /etc/modules-load.d/k3s.conf << EOF
overlay
br_netfilter
EOF

cat > /etc/modules-load.d/longhorn.conf << EOF
nfs
dm_crypt
EOF

# Kernel settings for k3s
cat > /etc/sysctl.d/k3s.conf << EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# ─── DockerHub auth (registries.yaml) ────────────────────────────────────────
mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/registries.yaml << EOF
configs:
  "registry-1.docker.io":
    auth:
      username: "${dockerhub_username}"
      password: "${dockerhub_token}"
EOF
chmod 600 /etc/rancher/k3s/registries.yaml

# ─── Wait for init node (secondary nodes only) ───────────────────────────────
%{~ if !is_init_node }
until curl -sk "https://${init_node_ip}:6443/ping" > /dev/null 2>&1; do
  echo "Waiting for init node API at ${init_node_ip}:6443..."
  sleep 10
done
%{~ endif }

# ─── Install k3s server ───────────────────────────────────────────────────────
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${k3s_version}" \
  K3S_TOKEN="${k3s_token}" \
  sh -s - server \
%{~ if is_init_node }
    --cluster-init \
%{~ else }
    --server "https://${init_node_ip}:6443" \
%{~ endif }
    --tls-san "${ingress_eip}" \
    --tls-san "${server_private_ip}" \
    --node-ip "${server_private_ip}" \
    --advertise-address "${server_private_ip}" \
    --disable servicelb \
    --disable local-storage \
%{~ if disable_traefik }
    --disable traefik \
%{~ endif }
    --write-kubeconfig-mode 644 \
    --etcd-s3 \
    --etcd-s3-bucket "${etcd_backup_bucket}" \
    --etcd-s3-region "${aws_region}" \
    --etcd-snapshot-schedule-cron "0 */6 * * *" \
    --etcd-snapshot-retention 10 \
    --node-label "role=server" \
    --node-label "cluster=${cluster_name}"

# Wait for k3s to be ready
until kubectl get nodes 2>/dev/null | grep -q "Ready"; do
  echo "Waiting for k3s to be ready..."
  sleep 5
done

echo "k3s server setup complete" >> /var/log/userdata.log