#!/bin/bash
set -euo pipefail

hostnamectl set-hostname ${cluster_name}-${worker_name}

# ─── System prep ─────────────────────────────────────────────────────────────
dnf update -y
dnf install -y epel-release
dnf install -y curl wget git vim htop iptables-services container-selinux

# Longhorn dependencies
dnf install -y iscsi-initiator-utils nfs-utils cryptsetup
systemctl enable --now iscsid

# Disable swap
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Kernel modules
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

cat > /etc/sysctl.d/k3s.conf << EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# ─── Longhorn disk prep ───────────────────────────────────────────────────────
# Wait for Longhorn disk to be available
LONGHORN_DISK="${longhorn_disk}"
while [ ! -b "$LONGHORN_DISK" ]; do
  echo "Waiting for Longhorn disk $LONGHORN_DISK..."
  sleep 3
done

# Format only if not already formatted
if ! blkid "$LONGHORN_DISK" > /dev/null 2>&1; then
  mkfs.ext4 -F "$LONGHORN_DISK"
fi

# Mount Longhorn disk
mkdir -p /var/lib/longhorn
DISK_UUID=$(blkid -s UUID -o value "$LONGHORN_DISK")
echo "UUID=$DISK_UUID /var/lib/longhorn ext4 defaults,nofail 0 2" >> /etc/fstab
mount -a

# ─── DockerHub auth ───────────────────────────────────────────────────────────
mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/registries.yaml << EOF
configs:
  "registry-1.docker.io":
    auth:
      username: "${dockerhub_username}"
      password: "${dockerhub_token}"
EOF
chmod 600 /etc/rancher/k3s/registries.yaml

# ─── Wait for k3s server to be ready ─────────────────────────────────────────
until curl -sk "https://${k3s_server_ip}:6443/ping" > /dev/null 2>&1; do
  echo "Waiting for k3s API server at ${k3s_server_ip}:6443..."
  sleep 10
done

# ─── Install k3s agent ───────────────────────────────────────────────────────
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${k3s_version}" \
  K3S_URL="https://${k3s_server_ip}:6443" \
  K3S_TOKEN="${k3s_token}" \
  sh -s - agent \
    --node-ip "${worker_private_ip}" \
    --node-label "role=worker" \
    --node-label "cluster=${cluster_name}" \
    --node-label "longhorn=true"

echo "k3s worker ${worker_name} setup complete" >> /var/log/userdata.log