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

echo "Bastion setup complete" >> /var/log/userdata.log