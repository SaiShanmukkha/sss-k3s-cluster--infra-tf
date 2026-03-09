# k3s Cluster — Full Setup & Installation Guide

End-to-end walkthrough from zero to a running HA k3s cluster on AWS. Covers Terraform provisioning,
SSH access, k3s installation verification, manual recovery if the automated install failed, and
Traefik ingress setup.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites](#2-prerequisites)
3. [Configure Terraform Variables](#3-configure-terraform-variables)
4. [Run Terraform](#4-run-terraform)
5. [Capture Terraform Outputs](#5-capture-terraform-outputs)
6. [Set Up SSH Access](#6-set-up-ssh-access)
7. [Verify Automated k3s Installation](#7-verify-automated-k3s-installation)
8. [Manual k3s Installation (if userdata failed)](#8-manual-k3s-installation-if-userdata-failed)
9. [Set Up Kubeconfig on Bastion](#9-set-up-kubeconfig-on-bastion)
10. [Verify the Cluster](#10-verify-the-cluster)
11. [Verify Ingress Layer (HAProxy + Keepalived)](#11-verify-ingress-layer-haproxy--keepalived)
12. [Install Traefik Ingress Controller](#12-install-traefik-ingress-controller)
13. [DNS Setup](#13-dns-setup)
14. [Post-Install Checklist](#14-post-install-checklist)
15. [Common Issues & Fixes](#15-common-issues--fixes)

---

## 1. Architecture Overview

```
Internet
   │
   ├─► Bastion EIP (SSH :22)           ← admin access only
   │
   └─► Ingress floating EIP            ← all app traffic (*.yourdomain.com)
         │
         ├─ ingress-1  HAProxy MASTER  + Keepalived  (ap-south-1a, public)
         └─ ingress-2  HAProxy BACKUP  + Keepalived  (ap-south-1b, public)
               │
               ├─ :80   → worker nodes :30080  (Traefik HTTP  NodePort)
               ├─ :443  → worker nodes :30443  (Traefik HTTPS NodePort)
               └─ :6443 → server nodes :6443   (k3s API)
```

### Node Inventory

| Role          | AZ           | Private IP    | EC2 Name              |
|---------------|--------------|---------------|-----------------------|
| k3s-server-1  | ap-south-1a  | 10.0.11.10    | sss-k3s-dev-k3s-server-1 |
| k3s-server-2  | ap-south-1b  | 10.0.12.10    | sss-k3s-dev-k3s-server-2 |
| k3s-server-3  | ap-south-1c  | 10.0.13.10    | sss-k3s-dev-k3s-server-3 |
| k3s-worker-1  | ap-south-1a  | 10.0.11.20    | sss-k3s-dev-worker-1 |
| k3s-worker-2  | ap-south-1b  | 10.0.12.20    | sss-k3s-dev-worker-2 |
| k3s-worker-3  | ap-south-1c  | 10.0.13.20    | sss-k3s-dev-worker-3 |
| ingress-1     | ap-south-1a  | (public EIP)  | sss-k3s-dev-ingress-1 |
| ingress-2     | ap-south-1b  | 10.0.2.10     | sss-k3s-dev-ingress-2 |
| bastion       | ap-south-1a  | (public EIP)  | sss-k3s-dev-bastion  |

**k3s-server-1 is the init node** (`--cluster-init`). Servers 2 and 3 join it via `--server`. All
three form an embedded etcd quorum. Workers connect to server-1's private IP.

---

## 2. Prerequisites

### Local Machine

| Tool          | Version       | Install                                       |
|---------------|---------------|-----------------------------------------------|
| Terraform     | ≥ 1.6         | https://developer.hashicorp.com/terraform/install |
| AWS CLI       | v2            | https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html |
| OpenSSH       | any           | Built-in on Linux/macOS/WSL; installed with Git for Windows |

### AWS Account

- IAM user / role with permissions for: EC2, VPC, IAM, S3, Route53, EIP
- AWS credentials configured locally:

```bash
aws configure
# or
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_DEFAULT_REGION=ap-south-1
```

### DockerHub Account

Required to avoid Docker Hub pull-rate limits on the cluster nodes. A free account is enough.
Create a read-only access token at https://hub.docker.com/settings/security.

---

## 3. Configure Terraform Variables

### 3a. Public variables — `terraform.tfvars`

Most values are already set. Review these before applying:

```hcl
region       = "ap-south-1"
project_name = "sss-k3s"
environment  = "dev"

k3s_version = "v1.35.2+k3s1"   # pin exact version, e.g. v1.29.3+k3s1

route53_hosted_zone_id = "REPLACE_WITH_HOSTED_ZONE_ID"   # your Route53 zone
```

- `k3s_version` — find current stable releases at https://github.com/k3s-io/k3s/releases.
  Always pin a specific version (e.g. `v1.29.3+k3s1`) so nodes don't drift.
- `route53_hosted_zone_id` — needed by cert-manager later for DNS-01 challenges.

### 3b. Sensitive variables — `secrets.auto.tfvars`

This file is **gitignored**. Create it if it doesn't exist:

```bash
# secrets.auto.tfvars
k3s_token              = ""   # see generation command below
dockerhub_username     = ""
dockerhub_token        = ""
keepalived_auth_pass   = ""   # max 8 chars
haproxy_stats_password = ""
```

Generate the required secrets:

```bash
# k3s cluster join token (shared by all nodes)
openssl rand -hex 32

# keepalived VRRP password (max 8 chars)
openssl rand -base64 6
```

Fill in `secrets.auto.tfvars` with those values. **Never commit this file.**

---

## 4. Run Terraform

```bash
cd s:\terraform\sss-k3s-cluster   # Windows
# or
cd /path/to/sss-k3s-cluster       # Linux/WSL

# Initialise providers and modules
terraform init

# Preview what will be created (no changes made)
terraform plan

# Apply — creates ~40+ AWS resources; takes 3-5 min
terraform apply
```

Type `yes` when prompted.

### What Terraform Creates (in order)

| Step | Module              | Resources created                                     |
|------|---------------------|-------------------------------------------------------|
| 1    | vpc                 | VPC, 3 public subnets, 3 private subnets, IGW, NAT GW, route tables |
| 2    | security_groups     | SG for bastion, ingress, k3s-server, k3s-worker      |
| 3    | keypair             | Two RSA key pairs; PEM files saved to `./keys/`      |
| 4    | iam                 | Instance profiles for bastion, ingress, server, worker |
| 5    | s3                  | etcd-backups, velero-backups, longhorn-backups buckets |
| 6    | ingress             | 2× EC2 (HAProxy + Keepalived), 1 floating EIP        |
| 7    | bastion             | 1× EC2 with kubectl, helm, k9s pre-installed         |
| 8    | k3s_server_init     | 1× EC2 (k3s-server-1, `--cluster-init`)              |
| 8    | k3s_servers_secondary | 2× EC2 (k3s-server-2/3, join init node)            |
| 9    | k3s_workers         | 3× EC2 Spot (one per AZ, join server-1)              |

The userdata scripts run automatically on first boot and install k3s on each node.

---

## 5. Capture Terraform Outputs

After `terraform apply`:

```bash
terraform output bastion_public_ip      # SSH entrypoint
terraform output ingress_eip            # Point *.yourdomain.com here
```

Keys are written to `./keys/`:
```
keys/sss-k3s-dev-admin-key.pem      ← bastion access
keys/sss-k3s-dev-internal-key.pem   ← all internal nodes
```

On Linux/WSL, fix key permissions:
```bash
chmod 600 keys/*.pem
```

---

## 6. Set Up SSH Access

### 6a. Method 1 — Agent Forwarding (recommended)

**Linux/WSL/macOS:**

```bash
eval $(ssh-agent -s)
ssh-add ./keys/sss-k3s-dev-admin-key.pem
ssh-add ./keys/sss-k3s-dev-internal-key.pem
ssh-add -l   # verify both keys loaded
```

**Windows (PowerShell as Administrator, once):**

```powershell
Set-Service ssh-agent -StartupType Automatic
Start-Service ssh-agent
ssh-add S:\terraform\sss-k3s-cluster\keys\sss-k3s-dev-admin-key.pem
ssh-add S:\terraform\sss-k3s-cluster\keys\sss-k3s-dev-internal-key.pem
```

SSH to bastion with forwarding:

```bash
ssh -A -i ./keys/sss-k3s-dev-admin-key.pem rocky@<bastion_public_ip>
```

From the bastion, reach any internal node:

```bash
ssh rocky@10.0.11.10   # k3s-server-1  (init node)
ssh rocky@10.0.12.10   # k3s-server-2
ssh rocky@10.0.13.10   # k3s-server-3
ssh rocky@10.0.11.20   # worker-1
ssh rocky@10.0.12.20   # worker-2
ssh rocky@10.0.13.20   # worker-3
```

### 6b. Method 2 — ProxyJump via SSH config

Add to `~/.ssh/config` (Linux/macOS) or `C:\Users\<you>\.ssh\config` (Windows):

```
Host bastion
  HostName        <bastion_public_ip>
  User            rocky
  IdentityFile    ~/keys/sss-k3s-dev-admin-key.pem
  ForwardAgent    yes

Host 10.0.*.*
  User            rocky
  IdentityFile    ~/keys/sss-k3s-dev-internal-key.pem
  ProxyJump       bastion
```

Then from your local machine directly:

```bash
ssh 10.0.11.10   # reaches k3s-server-1 through bastion automatically
```

---

## 7. Verify Automated k3s Installation

Each node's userdata script runs on first boot. Allow **5-10 minutes** after `terraform apply`
before checking — the script updates the OS, loads kernel modules, and downloads k3s.

### 7a. Check userdata completion log

SSH to each server node and check:

```bash
# On k3s-server-1 (10.0.11.10)
sudo cat /var/log/userdata.log
# Expected output:
# k3s server setup complete
```

```bash
# On each worker (10.0.11.20 / 10.0.12.20 / 10.0.13.20)
sudo cat /var/log/userdata.log
# Expected output:
# k3s worker <name> setup complete
```

### 7b. Check k3s service status

```bash
# On any server node
sudo systemctl status k3s
# Should show: active (running)

# On any worker node
sudo systemctl status k3s-agent
# Should show: active (running)
```

### 7c. Check from bastion

```bash
# After kubeconfig is set up (see section 9):
kubectl get nodes -o wide
```

Expected output (all 6 nodes `Ready`):

```
NAME                    STATUS   ROLES                       AGE   VERSION
sss-k3s-dev-k3s-server-1   Ready    control-plane,etcd,master   ...   v1.x.x+k3s1
sss-k3s-dev-k3s-server-2   Ready    control-plane,etcd,master   ...   v1.x.x+k3s1
sss-k3s-dev-k3s-server-3   Ready    control-plane,etcd,master   ...   v1.x.x+k3s1
sss-k3s-dev-worker-1        Ready    <none>                      ...   v1.x.x+k3s1
sss-k3s-dev-worker-2        Ready    <none>                      ...   v1.x.x+k3s1
sss-k3s-dev-worker-3        Ready    <none>                      ...   v1.x.x+k3s1
```

---

## 8. Manual k3s Installation (if userdata failed)

Run these steps if the automated install did not complete (e.g. `userdata.log` is missing or
shows an error, or `systemctl status k3s` shows inactive/failed).

### 8a. Diagnose the failure first

```bash
# On the affected node:
sudo journalctl -u cloud-final --no-pager | tail -50
sudo cat /var/log/cloud-init-output.log | tail -100
```

Common causes:
- Network not ready when script ran → NAT Gateway not up yet
- K3s version string invalid
- DockerHub token / k3s_token not substituted (template rendering issue)

### 8b. Prepare system (all nodes — run if not already done)

```bash
# Update OS
sudo dnf update -y
sudo dnf install -y curl wget git vim htop iptables-services container-selinux

# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Kernel modules
sudo modprobe overlay
sudo modprobe br_netfilter

sudo tee /etc/modules-load.d/k3s.conf << EOF
overlay
br_netfilter
EOF

sudo tee /etc/sysctl.d/k3s.conf << EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
```

### 8c. Create registries.yaml (DockerHub auth — all nodes)

```bash
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/registries.yaml << EOF
configs:
  "registry-1.docker.io":
    auth:
      username: "<your-dockerhub-username>"
      password: "<your-dockerhub-token>"
EOF
sudo chmod 600 /etc/rancher/k3s/registries.yaml
```

### 8d. Install k3s on the Init Node (`k3s-server-1` — 10.0.11.10)

> **Run this on k3s-server-1 only.** This starts the etcd cluster.

```bash
# Set these variables first
K3S_VERSION="v1.35.2+k3s1"        # match your terraform.tfvars
K3S_TOKEN="<your-k3s-token>"      # from secrets.auto.tfvars
INGRESS_EIP="<ingress-eip>"       # from: terraform output ingress_eip
SERVER_IP="10.0.11.10"            # this node's private IP

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="$K3S_VERSION" \
  K3S_TOKEN="$K3S_TOKEN" \
  sh -s - server \
    --cluster-init \
    --tls-san "$INGRESS_EIP" \
    --tls-san "$SERVER_IP" \
    --node-ip "$SERVER_IP" \
    --advertise-address "$SERVER_IP" \
    --disable servicelb \
    --disable local-storage \
    --disable traefik \
    --write-kubeconfig-mode 644 \
    --etcd-s3 \
    --etcd-s3-bucket "sss-k3s-dev-etcd-backups" \
    --etcd-s3-region "ap-south-1" \
    --etcd-snapshot-schedule-cron "0 */6 * * *" \
    --etcd-snapshot-retention 10 \
    --node-label "role=server" \
    --node-label "cluster=sss-k3s-dev"
```

Verify it started:

```bash
sudo systemctl status k3s
sudo kubectl get nodes
```

Wait until `k3s-server-1` appears as `Ready` before continuing.

### 8e. Join Secondary Server Nodes (`k3s-server-2`, `k3s-server-3`)

> Run on **k3s-server-2** (10.0.12.10) and **k3s-server-3** (10.0.13.10) individually.

```bash
K3S_VERSION="v1.35.2+k3s1"
K3S_TOKEN="<your-k3s-token>"
INGRESS_EIP="<ingress-eip>"
INIT_NODE_IP="10.0.11.10"         # server-1 is always the init node
THIS_NODE_IP="10.0.12.10"         # change to 10.0.13.10 for server-3

# Wait for the init node API to be available
until curl -sk "https://$INIT_NODE_IP:6443/ping" > /dev/null 2>&1; do
  echo "Waiting for init node API..."
  sleep 10
done

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="$K3S_VERSION" \
  K3S_TOKEN="$K3S_TOKEN" \
  sh -s - server \
    --server "https://$INIT_NODE_IP:6443" \
    --tls-san "$INGRESS_EIP" \
    --tls-san "$THIS_NODE_IP" \
    --node-ip "$THIS_NODE_IP" \
    --advertise-address "$THIS_NODE_IP" \
    --disable servicelb \
    --disable local-storage \
    --disable traefik \
    --write-kubeconfig-mode 644 \
    --etcd-s3 \
    --etcd-s3-bucket "sss-k3s-dev-etcd-backups" \
    --etcd-s3-region "ap-south-1" \
    --etcd-snapshot-schedule-cron "0 */6 * * *" \
    --etcd-snapshot-retention 10 \
    --node-label "role=server" \
    --node-label "cluster=sss-k3s-dev"
```

Verify from server-1:

```bash
# On k3s-server-1:
sudo kubectl get nodes
```

Both new servers should appear as `Ready` with role `control-plane,etcd,master`.

### 8f. Prepare Worker Nodes (Longhorn disk)

Each worker has a dedicated EBS volume for Longhorn. Run on **each worker** before joining k3s:

```bash
# Find the Longhorn disk (usually /dev/nvme1n1 or /dev/xvdb)
lsblk
LONGHORN_DISK="/dev/nvme1n1"   # adjust if different

# Format only if unformatted
if ! sudo blkid "$LONGHORN_DISK" > /dev/null 2>&1; then
  sudo mkfs.ext4 -F "$LONGHORN_DISK"
fi

# Mount persistently
sudo mkdir -p /var/lib/longhorn
DISK_UUID=$(sudo blkid -s UUID -o value "$LONGHORN_DISK")
echo "UUID=$DISK_UUID /var/lib/longhorn ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
sudo mount -a

# Verify mount
df -h /var/lib/longhorn
```

### 8g. Join Worker Nodes

Run on **each worker** (10.0.11.20, 10.0.12.20, 10.0.13.20):

```bash
K3S_VERSION="v1.35.2+k3s1"
K3S_TOKEN="<your-k3s-token>"
K3S_SERVER_IP="10.0.11.10"        # server-1 private IP
WORKER_IP="10.0.11.20"            # this worker's private IP (adjust per node)

# Wait for server API
until curl -sk "https://$K3S_SERVER_IP:6443/ping" > /dev/null 2>&1; do
  echo "Waiting for k3s API at $K3S_SERVER_IP:6443..."
  sleep 10
done

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="$K3S_VERSION" \
  K3S_URL="https://$K3S_SERVER_IP:6443" \
  K3S_TOKEN="$K3S_TOKEN" \
  sh -s - agent \
    --node-ip "$WORKER_IP" \
    --node-label "role=worker" \
    --node-label "cluster=sss-k3s-dev" \
    --node-label "longhorn=true"
```

Verify from server-1:

```bash
sudo kubectl get nodes -o wide
# All 6 nodes should be Ready
```

---

## 9. Set Up Kubeconfig on Bastion

The bastion has `kubectl`, `helm`, and `k9s` pre-installed via userdata. You need to copy the
kubeconfig from the init server.

### 9a. SSH chain: local → bastion → server-1

From your **local machine**:

```bash
# 1. SSH to bastion (with agent forwarding)
ssh -A -i ./keys/sss-k3s-dev-admin-key.pem rocky@<bastion_public_ip>
```

From the **bastion**:

```bash
# 2. Copy kubeconfig from server-1
mkdir -p ~/.kube
ssh rocky@10.0.11.10 "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/config

# 3. Replace the loopback IP with the server-1 private IP
sed -i 's|https://127.0.0.1:6443|https://10.0.11.10:6443|g' ~/.kube/config

chmod 600 ~/.kube/config
```

### 9b. Verify kubectl works

```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A
```

### 9c. Access via ingress EIP (optional)

If you want to access the k3s API from outside the VPC (e.g. from your local machine), the
HAProxy ingress nodes forward `:6443` to the server nodes. You can use:

```bash
# Replace the server address in kubeconfig with the ingress EIP
sed -i 's|https://10.0.11.10:6443|https://<ingress_eip>:6443|g' ~/.kube/config
```

The ingress EIP is included in the k3s TLS SANs so the certificate will be valid.

---

## 10. Verify the Cluster

Run all from the **bastion**:

```bash
# All 6 nodes Ready
kubectl get nodes -o wide

# System pods running (coredns, metrics-server, etc.)
kubectl get pods -n kube-system

# etcd cluster health
kubectl -n kube-system exec -it \
  $(kubectl -n kube-system get pods -l component=etcd -o name | head -1) \
  -- etcdctl endpoint health \
     --endpoints=https://10.0.11.10:2379,https://10.0.12.10:2379,https://10.0.13.10:2379 \
     --cacert /var/lib/rancher/k3s/server/tls/etcd/server-ca.crt \
     --cert   /var/lib/rancher/k3s/server/tls/etcd/client.crt \
     --key    /var/lib/rancher/k3s/server/tls/etcd/client.key

# Or directly on a server node:
sudo k3s etcd-snapshot ls
```

### Check Node Labels

```bash
kubectl get nodes --show-labels | grep -E "role=|longhorn="
```

Expected:
- Server nodes: `role=server`
- Worker nodes: `role=worker,longhorn=true`

### Check Resource Usage

```bash
kubectl top nodes     # requires metrics-server (included in k3s by default)
kubectl top pods -A
```

---

## 11. Verify Ingress Layer (HAProxy + Keepalived)

The ingress nodes are already provisioned by Terraform. Verify they are working correctly.

### 11a. SSH into ingress-1

From bastion:

```bash
ssh rocky@<ingress-1-private-ip>   # get from: terraform output ingress_1_public_ip
# or via public IP from local:
ssh -i ./keys/sss-k3s-dev-internal-key.pem rocky@<ingress_1_public_ip>
```

### 11b. Check HAProxy status

```bash
sudo systemctl status haproxy
sudo haproxy -c -f /etc/haproxy/haproxy.cfg   # validate config

# Stats page (internal access)
curl -s http://localhost:8404/stats | grep -E "UP|DOWN"
```

### 11c. Check Keepalived

```bash
sudo systemctl status keepalived

# MASTER node should show the VIP is held
ip addr show eth0 | grep -E "inet "
```

### 11d. Test port connectivity

From **bastion**, test that HAProxy is forwarding correctly:

```bash
INGRESS_EIP="<ingress_eip>"

# Test k3s API forwarding
curl -sk https://$INGRESS_EIP:6443/ping && echo "k3s API: OK"

# Test HTTP (80) — will return nothing until Traefik is installed
nc -zv $INGRESS_EIP 80 && echo "HTTP: OK"

# Test HTTPS (443)
nc -zv $INGRESS_EIP 443 && echo "HTTPS: OK"
```

---

## 12. Install Traefik Ingress Controller

Traefik is disabled in the k3s install flags (`--disable traefik`) so it can be fully configured
via Helm. HAProxy is already configured to forward `:80 → :30080` and `:443 → :30443` on the
worker nodes.

See **[01-traefik.md](01-traefik.md)** for the full installation guide with Helm values.

Quick summary:

```bash
# On bastion:

# Add Traefik Helm repo
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Create namespace
kubectl create namespace traefik

# Install (values in 01-traefik.md)
helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --values ~/traefik-values.yaml \
  --wait

# Verify Traefik pods are running on worker nodes
kubectl get pods -n traefik -o wide
```

After Traefik is installed, test end-to-end:

```bash
# Deploy a test echo server
kubectl run echo --image=ealen/echo-server --port=80
kubectl expose pod echo --port=80 --name=echo-svc

cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: echo-ingress
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
spec:
  ingressClassName: traefik
  rules:
  - host: echo.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: echo-svc
            port:
              number: 80
EOF

# Test (replace with your domain)
curl -k https://echo.yourdomain.com
```

Clean up after testing:

```bash
kubectl delete ingress echo-ingress
kubectl delete svc echo-svc
kubectl delete pod echo
```

---

## 13. DNS Setup

Point your domain's DNS records to the **ingress floating EIP**.

```bash
terraform output ingress_eip
```

### Route53 (recommended — used by cert-manager)

In your Route53 hosted zone (`route53_hosted_zone_id` in tfvars):

| Record | Type | Value                  |
|--------|------|------------------------|
| `*`    | A    | `<ingress_eip>`        |
| `@`    | A    | `<ingress_eip>`        |

Using AWS CLI:

```bash
HOSTED_ZONE_ID="<your-zone-id>"
INGRESS_EIP="<ingress_eip>"
DOMAIN="yourdomain.com"

aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch "{
    \"Changes\": [{
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"*.$DOMAIN\",
        \"Type\": \"A\",
        \"TTL\": 300,
        \"ResourceRecords\": [{\"Value\": \"$INGRESS_EIP\"}]
      }
    }]
  }"
```

DNS changes typically propagate within 1-5 minutes for Route53.

---

## 14. Post-Install Checklist

Work through this checklist after the cluster is up and all nodes are `Ready`.

```
[ ] terraform apply completed successfully
[ ] All 6 nodes visible: kubectl get nodes (all Ready)
[ ] k3s-server-1 is MASTER (role: control-plane,etcd,master)
[ ] etcd quorum healthy (3 members)
[ ] kube-system pods running: kubectl get pods -n kube-system
[ ] HAProxy active on ingress-1 and ingress-2
[ ] Keepalived MASTER on ingress-1, BACKUP on ingress-2
[ ] Floating EIP responding on :6443, :80, :443
[ ] Kubeconfig set up on bastion (kubectl cluster-info works)
[ ] Docker Hub registries.yaml present on all nodes (prevents pull limits)
[ ] etcd S3 backups configured (check: sudo k3s etcd-snapshot ls on server-1)
[ ] Traefik installed and pods running on worker nodes (see 01-traefik.md)
[ ] Wildcard DNS *.yourdomain.com → ingress EIP configured
[ ] cert-manager installed for TLS (see 02-cert-manager.md)
[ ] Longhorn installed for persistent volumes (see 03-longhorn.md)
```

---

## 15. Common Issues & Fixes

### k3s service fails to start on server-1

```bash
sudo journalctl -u k3s -n 100 --no-pager
```

- **"address already in use" on :6443** → another process is using the port. Check `ss -tlnp | grep 6443`.
- **etcd TLS errors** → delete `/var/lib/rancher/k3s/server/db/` and restart. Only do this on a fresh node.
- **"token does not match"** → the `K3S_TOKEN` used on secondary nodes doesn't match what server-1 was installed with.

### Secondary server can't join init node

```bash
# On secondary server, confirm it can reach server-1 API:
curl -sk https://10.0.11.10:6443/ping
```

If it times out, the security group or subnet routing is blocking the connection. Verify:
- The k3s-server security group allows `:6443` inbound from all private subnets.
- The private subnets have a route to the NAT gateway for internet access.

### Worker can't join cluster

```bash
# On the worker node:
sudo journalctl -u k3s-agent -n 100 --no-pager
```

- **Certificate error** → the node's clock may be out of sync. Run: `sudo chronyc -a makestep`
- **Connection refused** → server-1 is not yet ready. Wait and retry.
- **Token mismatch** → use the exact same token value as the server install.

### HAProxy shows workers as DOWN

Traefik is not yet running on the workers. HAProxy performs health checks on `:30080` and `:30443`.
These will only pass once Traefik is installed. See [section 12](#12-install-traefik-ingress-controller).

### kubectl shows nodes NotReady

```bash
kubectl describe node <node-name>
# Look for conditions: MemoryPressure, DiskPressure, NetworkUnavailable
```

- **DiskPressure** → disk is >85% full. Check `df -h` on the node.
- **NetworkUnavailable** → Flannel CNI not running. Check: `kubectl get pods -n kube-system | grep flannel`

### etcd S3 backup not working

```bash
# On server-1:
sudo systemctl status k3s
sudo journalctl -u k3s | grep -i etcd

# Verify IAM instance profile has S3 write permissions:
aws s3 ls s3://sss-k3s-dev-etcd-backups/

# Trigger a manual snapshot:
sudo k3s etcd-snapshot save --name manual-test
sudo k3s etcd-snapshot ls
```

---

*Next steps: [02-cert-manager.md](02-cert-manager.md) → [03-longhorn.md](03-longhorn.md) → [04-rancher.md](04-rancher.md)*
