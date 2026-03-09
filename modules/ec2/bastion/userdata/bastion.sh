#!/bin/bash
set -euo pipefail

hostnamectl set-hostname ${cluster_name}-bastion

# Update and install essentials
dnf update -y
dnf install -y epel-release
dnf install -y \
  curl wget git vim htop tmux \
  net-tools bind-utils telnet \
  bash-completion

# Harden SSH
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

# Install kubectl for cluster management from bastion
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install k9s — terminal UI for k8s
K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | grep tag_name | cut -d'"' -f4)
curl -sL "https://github.com/derailed/k9s/releases/download/$${K9S_VERSION}/k9s_Linux_amd64.tar.gz" | tar xz -C /usr/local/bin k9s

# SSH agent forwarding config
cat >> /etc/ssh/sshd_config << 'EOF'
AllowAgentForwarding yes
EOF
systemctl restart sshd

# ─── Helm UI secrets ─────────────────────────────────────────────────────────
# Written once at boot; source this file before running helm install commands.
# Plain passwords are hashed here so Kubernetes secrets hold only hashed values.
dnf install -y httpd-tools   # provides htpasswd

TRAEFIK_HTPASSWD=$(htpasswd -nb admin '${traefik_dashboard_password}')
LONGHORN_HTPASSWD=$(htpasswd -nb admin '${longhorn_ui_password}' | base64)

cat > /root/helm-secrets.env << ENVSECRETS
# Source this file before running helm install / upgrade commands:
#   source ~/helm-secrets.env
export RANCHER_BOOTSTRAP_PASSWORD='${rancher_bootstrap_password}'
export TRAEFIK_DASHBOARD_HTPASSWD='$${TRAEFIK_HTPASSWD}'
export LONGHORN_UI_HTPASSWD_B64='$${LONGHORN_HTPASSWD}'
export GRAFANA_ADMIN_PASSWORD='${grafana_admin_password}'
ENVSECRETS
chmod 600 /root/helm-secrets.env

echo "Bastion setup complete" >> /var/log/userdata.log