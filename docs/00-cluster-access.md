# Cluster Access

How to reach the k3s cluster after `terraform apply` completes.

## Architecture

```
Internet
   │
   ├─► Bastion EIP (SSH)       ← admin access
   │
   └─► Ingress floating EIP    ← all app traffic (*.yourdomain.com)
         │
         ├─ ingress-1 (HAProxy MASTER + Keepalived)
         └─ ingress-2 (HAProxy BACKUP + Keepalived)
               │
               ├─ :30080 → workers (Traefik HTTP)
               ├─ :30443 → workers (Traefik HTTPS)
               └─ :6443  → servers (k3s API)
```

## Get Outputs

After `terraform apply`:

```bash
terraform output bastion_public_ip      # SSH entry point
terraform output ingress_eip            # Point *.yourdomain.com here
# Keys are written automatically to keys/ by Terraform:
#   keys/sss-k3s-dev-admin-key.pem    — bastion
#   keys/sss-k3s-dev-internal-key.pem — internal nodes
```

## SSH to Bastion

```bash
ssh -i keys/sss-k3s-dev-admin-key.pem rocky@<bastion_public_ip>
```

## SSH to Internal Nodes (via Bastion)

Run all commands on your **local machine**. Both methods use the keys written to `./keys/` by Terraform.

### Method 1 — Agent Forwarding

**Linux/WSL/macOS:**

```bash
eval $(ssh-agent -s)
ssh-add ./keys/sss-k3s-dev-admin-key.pem
ssh-add ./keys/sss-k3s-dev-internal-key.pem
ssh-add -l  # verify both are loaded
```

**Windows (PowerShell):**

```ps1
Start-Service ssh-agent
ssh-add S:\terraform\sss-k3s-cluster\keys\sss-k3s-dev-admin-key.pem
ssh-add S:\terraform\sss-k3s-cluster\keys\sss-k3s-dev-internal-key.pem
```

Connect to the bastion with agent forwarding:

```bash
ssh -A -i keys/sss-k3s-dev-admin-key.pem rocky@<bastion_public_ip>
```

From the bastion, SSH to any internal node (agent is forwarded):

```bash
ssh rocky@10.0.11.10   # k3s-server-1
ssh rocky@10.0.12.10   # k3s-server-2
ssh rocky@10.0.13.10   # k3s-server-3
ssh rocky@10.0.11.20   # worker-1
ssh rocky@10.0.12.20   # worker-2
ssh rocky@10.0.13.20   # worker-3
ssh rocky@<ingress-1-private-ip>  # ingress-1
```

### Method 2 — ProxyJump (SSH config)

Add to your SSH config on your local machine:

```
~/.ssh/config                          # Linux/WSL/macOS
C:\Users\<your-username>\.ssh\config   # Windows
```

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

Then from your local machine:

```bash
ssh bastion        # connect to bastion
ssh 10.0.11.10     # jumps through bastion automatically
ssh 10.0.11.20     # worker-1, etc.
```

## First kubectl Access (from Bastion)

The kubeconfig is written world-readable on the init server:

```bash
# On bastion — copy kubeconfig from server-1
mkdir -p ~/.kube
ssh 10.0.11.10 "cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/config

# Replace the embedded server URL with the init-node IP
sed -i 's|https://127.0.0.1:6443|https://10.0.11.10:6443|' ~/.kube/config
chmod 600 ~/.kube/config

# Verify
kubectl get nodes -o wide
```

Expected output:
```
NAME              STATUS   ROLES                       AGE   VERSION
sss-k3s-dev-k3s-server-1   Ready    control-plane,etcd,master   5m    v1.35.2+k3s1
sss-k3s-dev-k3s-server-2   Ready    control-plane,etcd,master   4m    v1.35.2+k3s1
sss-k3s-dev-k3s-server-3   Ready    control-plane,etcd,master   4m    v1.35.2+k3s1
sss-k3s-dev-worker-1       Ready    <none>                      3m    v1.35.2+k3s1
sss-k3s-dev-worker-2       Ready    <none>                      3m    v1.35.2+k3s1
sss-k3s-dev-worker-3       Ready    <none>                      3m    v1.35.2+k3s1
```

## DNS Setup

Point a wildcard record at the ingress floating EIP **before** installing any app:

```
*.yourdomain.com  →  A  →  <ingress_eip>   (TTL 300)
rancher.yourdomain.com → A → <ingress_eip>  (or covered by wildcard)
```

## Add Helm Repos (run once on bastion)

```bash
helm repo add traefik        https://helm.traefik.io/traefik
helm repo add jetstack       https://charts.jetstack.io
helm repo add longhorn       https://charts.longhorn.io
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add vmware-tanzu   https://vmware-tanzu.github.io/helm-charts
helm repo update
```

## Installation Order

Install in this sequence — each depends on the previous:

1. **Traefik** — ingress controller (NodePorts 30080/30443)
2. **cert-manager** — TLS certificates (depends on Traefik for HTTP-01 or Route53 for DNS-01)
3. **Longhorn** — persistent storage (workers already have disks at `/var/lib/longhorn`)
4. **Rancher** — cluster management UI (depends on cert-manager + Longhorn)
5. **Monitoring** — Prometheus + Grafana (depends on Longhorn for persistence)
6. **Velero** — backup/restore (S3 bucket already provisioned by Terraform)
