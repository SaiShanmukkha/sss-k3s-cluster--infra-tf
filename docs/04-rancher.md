# Rancher — Kubernetes Management UI

Rancher provides a web UI to manage the cluster, deploy workloads, manage RBAC,
integrate with container registries, and view logs/metrics.

## Prerequisites

- Traefik installed and healthy (see `01-traefik.md`)
- cert-manager installed with a working `letsencrypt-prod` ClusterIssuer (see `02-cert-manager.md`)
- Longhorn installed and set as default StorageClass (see `03-longhorn.md`)
- DNS record: `rancher.yourdomain.com` → ingress floating EIP
- Helm repos added

## Install Rancher

```bash
kubectl create namespace cattle-system

#Genearte strong password
openssl rand -base64 32
#5WxvmeyAmqpEe+ivOnW6e4pIun4rXw11baJBpm7s5ns=

helm upgrade --install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --set hostname=rancher.yourdomain.com \
  --set bootstrapPassword=<strong-initial-password> \
  --set ingress.tls.source=secret \
  --set ingress.ingressClassName=traefik \
  --set replicas=3 \
  --set auditLog.level=1 \
  --set auditLog.destination=hostPath \
  --set antiAffinity=required \
  --set topologyKey=kubernetes.io/hostname \
  --version 2.13.3 \
  --wait --timeout 10m
```

> Check latest: `helm search repo rancher-stable/rancher --versions | head -5`

## Create TLS Certificate for Rancher

cert-manager handles the cert; create it manually so Rancher picks it up immediately:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: rancher-tls
  namespace: cattle-system
spec:
  secretName: tls-rancher-ingress
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - rancher.yourdomain.com
EOF

# Watch certificate issuance (30–90 seconds)
kubectl -n cattle-system get certificate rancher-tls -w
```

## Verify Rancher Deployment

```bash
kubectl -n cattle-system get pods
# rancher-* (3 pods) should all be Running

kubectl -n cattle-system rollout status deploy/rancher
# successfully rolled out

# Tail Rancher logs
kubectl -n cattle-system logs -l app=rancher -f --tail=50
```

## First Login

1. Open `https://rancher.yourdomain.com` in browser
2. Enter the `bootstrapPassword` you set above
3. Set a new permanent admin password
4. Set the Server URL to `https://rancher.yourdomain.com` (use the EIP-backed DNS name, not an IP)

## Import the Local Cluster into Rancher

Rancher installs on the cluster but you still need to **register** it so Rancher manages it:

1. In Rancher UI → **Cluster Management** → **Import Existing**
2. Choose **Import any Kubernetes cluster**
3. Name it (e.g. `sss-k3s-dev`)
4. Copy the `kubectl apply` command shown and run it from bastion
5. Wait ~2 minutes for agent pods to come up

```bash
kubectl get pods -n cattle-system
# cattle-cluster-agent-* Running
# cattle-node-agent-*     Running (one per node)
```

## Configure Rancher Authentication

### GitHub OAuth (recommended)

1. Rancher UI → ☰ → **Users & Authentication** → **Auth Provider** → **GitHub**
2. Enter your GitHub OAuth App credentials
   - Homepage URL: `https://rancher.yourdomain.com`
   - Callback URL: `https://rancher.yourdomain.com/verify-auth`
3. Under **Site Access**, restrict to your GitHub org

### RBAC — Restrict access to your team

```bash
# Give a GitHub user cluster-admin role via Rancher UI:
# Users & Authentication → Users → Add User
# Assign Global Role: Restricted Admin (can manage clusters but not Rancher settings)
```

## Configure Container Registry

So Rancher-launched workloads use your DockerHub credentials:

1. In Rancher UI → Cluster → **Storage** → **Secrets** → Create
2. Type: **Registry**
3. Registry: `registry-1.docker.io`
4. Username / Password: your DockerHub credentials
5. Namespace: `cattle-system` (or all namespaces)

Alternatively, via kubectl (note: `registries.yaml` on k3s nodes already handles this at the
system level — this is for Rancher-managed workload credentials):

```bash
kubectl create secret docker-registry dockerhub \
  --docker-server=registry-1.docker.io \
  --docker-username=<username> \
  --docker-password=<token> \
  --namespace default
```

## Enable Monitoring via Rancher

Rancher has a built-in Monitoring app (wraps kube-prometheus-stack). However, for full
control install it manually (see `05-monitoring.md`). The two approaches conflict —
choose one, not both.

To use Rancher's built-in:
1. Cluster → **Apps** → **Monitoring** → Install
2. Set Prometheus storage: Longhorn, 20Gi
3. Set Grafana storage: Longhorn, 5Gi

## Production Notes

- **`replicas: 3`** with `antiAffinity: required` spreads Rancher pods across workers.
  Rancher itself is stateless (state is in the cluster/etcd); 3 replicas ensure no downtime
  during Rancher pod restarts.
- **`bootstrapPassword`** is only used for first login. Change it immediately.
  Store it in a password manager — there is no recovery path without kubectl access.
- **Do not** set `ingress.tls.source=letsencrypt` — that uses a Rancher-internal ACME
  client which conflicts with cert-manager. Use `secret` and manage the cert separately.
- Rancher **2.8+** supports k3s as a managed distribution natively. Upgrade Rancher before
  upgrading k3s to avoid version compatibility gaps (check the support matrix:
  https://www.suse.com/suse-rancher/support-matrix/).
- **Backup Rancher state**: After initial setup, enable the Rancher Backup operator
  (available in Rancher's App Catalog) to back up Rancher's configuration to S3.
