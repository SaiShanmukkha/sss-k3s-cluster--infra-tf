# Longhorn — Distributed Block Storage

Longhorn provides replicated persistent volumes backed by the dedicated EBS disk
on each worker node. Each worker has a 50 GB gp3 EBS volume pre-formatted and
mounted at `/var/lib/longhorn` by the Terraform userdata script.

## Prerequisites

- All 3 worker nodes in Ready state
- Traefik installed (for the Longhorn UI ingress)
- cert-manager installed (for HTTPS on the UI)
- Helm repos added

## Verify Worker Disk Mounts

Before installing, confirm all workers have the Longhorn disk mounted:

```bash
for ip in worker-1 worker-2 worker-3; do
  echo "=== $ip ==="
  ssh rocky@$ip "df -h /var/lib/longhorn && lsblk /dev/nvme1n1"
done
```

Expected: `/var/lib/longhorn` mounted on `/dev/nvme1n1`, ~49 GB available.

> Note: `lsblk nvme1n1` (without `/dev/`) returns "not a block device" — always use the full path `/dev/nvme1n1`.

## Create Namespace

```bash
kubectl create namespace longhorn-system
```

> **If retrying after a failed install**, fully clean up first to avoid partial-state errors
> (`cannot be imported`, `not found` on CRDs, etc.):
> ```bash
> # Delete all leftover Longhorn CRDs
> kubectl get crd -o name | grep longhorn.io | xargs -r kubectl delete
>
> # Delete orphaned cluster-scoped resources
> kubectl get clusterrole,clusterrolebinding -o name | grep longhorn | xargs -r kubectl delete
>
> # Nuke and recreate the namespace
> kubectl delete namespace longhorn-system --ignore-not-found
> kubectl create namespace longhorn-system
> ```
> If the namespace is stuck in `Terminating`, force-remove it first:
> ```bash
> kubectl get namespace longhorn-system -o json \
>   | jq '.spec.finalizers = []' \
>   | kubectl replace --raw "/api/v1/namespaces/longhorn-system/finalize" -f -
> # Wait for it to disappear, then recreate:
> kubectl create namespace longhorn-system
> ```

## Install Longhorn System Dependencies

Longhorn requires `open-iscsi`, `nfs-utils`, and `cryptsetup` on every node, plus the `nfs`
and `dm_crypt` kernel modules. Run on all workers and servers from bastion:

```bash
for ip in server-1 server-2 server-3 \
          worker-1 worker-2 worker-3; do
  ssh rocky@$ip "
    sudo dnf install -y iscsi-initiator-utils nfs-utils cryptsetup && \
    sudo systemctl enable --now iscsid && \
    sudo modprobe nfs && sudo modprobe dm_crypt && \
    echo -e 'nfs\ndm_crypt' | sudo tee -a /etc/modules-load.d/longhorn.conf
  " &
done
wait
echo "All nodes ready"
```

Verify with `longhornctl` (replaced the old `longhorn-iscsi-installation.yaml` DaemonSet in v1.7.0+):
```bash
# Set the version you intend to install (find with: helm search repo longhorn/longhorn --versions | head -5)
LHVERSION=1.11.0

# AMD64
curl -sSfL -o longhornctl \
  https://github.com/longhorn/cli/releases/download/v${LHVERSION}/longhornctl-linux-amd64
chmod +x longhornctl
./longhornctl check preflight --kubeconfig=$HOME/.kube/config
```

> Note: `--kubeconfig=~/.kube/config` does **not** work — `longhornctl` doesn't expand `~`. Use `$HOME` or the full path.

All nodes should have **no `error:` entries** — only `info:` and at most this one `warn:`:
```
warn:
- '[KubeDNS] Kube DNS "coredns" is set with fewer than 2 replicas; ...'
```
The CoreDNS replica warning is a k3s default (single replica) and is **not a Longhorn blocker** — safe to proceed.

## values.yaml

Save as `~/longhorn-values.yaml`:

```yaml
defaultSettings:
  # Use the dedicated EBS disk, not the root volume
  defaultDataPath: /var/lib/longhorn

  # Replicate across all 3 workers for HA
  defaultReplicaCount: 3

  # Ensure replicas land on different nodes
  replicaSoftAntiAffinity: false   # false = HARD anti-affinity (required for prod)
  replicaAutoBalance: best-effort

  # S3 backup target (provisioned by Terraform)
  backupTarget: s3://sss-k3s-dev-longhorn-backups@ap-south-1/
  backupTargetCredentialSecret: longhorn-s3-secret
  # NOTE: a credential secret is REQUIRED even for IAM role access.
  # AWS_ACCESS_KEY_ID/SECRET_ACCESS_KEY must be ABSENT (not empty strings) —
  # Longhorn falls back to the EC2 instance profile only when these keys do not exist in the secret.

  # Reclaim space from deleted volumes automatically
  orphanAutoDeletion: true

  # Storage reserved on node for system (don't fill disk completely)
  storageMinimalAvailablePercentage: 15

  # Crash consistency on spot interruption
  restoreVolumeRecurringJobs: true

  # Node drain policy for spot interruptions
  nodeDrainPolicy: block-if-contains-last-replica

persistence:
  defaultClass: true          # make Longhorn the default StorageClass
  defaultClassReplicaCount: 3
  defaultFsType: ext4
  reclaimPolicy: Retain        # IMPORTANT: don't delete data on PVC delete in prod

# Deploy only on workers
longhornManager:
  nodeSelector:
    role: worker

longhornDriver:
  nodeSelector:
    role: worker

# Expose UI via Traefik
ingress:
  enabled: true
  ingressClassName: traefik
  host: longhorn.yourdomain.com    # ← replace
  tls: true
  tlsSecret: longhorn-tls
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    traefik.ingress.kubernetes.io/router.entrypoints: websecure

# UI authentication (add basic auth via Traefik middleware)
auth:
  secret: longhorn-auth

resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: "1"
    memory: 512Mi
```

## Install

```bash
# Use the same version you set above during prerequisites
helm upgrade --install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --values ~/longhorn-values.yaml \
  --version ${LHVERSION} \
  --wait --timeout 10m
```

> Pin a real version: `helm search repo longhorn/longhorn --versions | head -5`
>
> If you get any errors about existing CRDs or missing resources, use the **clean retry** steps
> in the "Create Namespace" section above, then re-run this command.

## Verify

```bash
kubectl -n longhorn-system get pods
# All pods should be Running

kubectl get storageclass
# longhorn (default)   longhorn.io/...   Retain   ...

kubectl get nodes.longhorn.io -n longhorn-system
# All 3 worker nodes should show schedulable = true

# Verify the default BackupTarget was created
kubectl get backuptarget -n longhorn-system
# NAME      AGE
# default   ...
```

> **If `default` BackupTarget is missing** (PVCs will fail with "backuptarget.longhorn.io default not found"),
> first create the S3 credential secret, then the BackupTarget:
> ```bash
> # AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must NOT be present at all (not even empty strings)
> # — their absence tells Longhorn to use the EC2 instance profile credential chain.
> kubectl apply -f - <<EOF
> apiVersion: v1
> kind: Secret
> metadata:
>   name: longhorn-s3-secret
>   namespace: longhorn-system
> type: Opaque
> stringData:
>   AWS_ENDPOINTS: ""
>   AWS_CERT: ""
> EOF
>
> kubectl apply -f - <<EOF
> apiVersion: longhorn.io/v1beta2
> kind: BackupTarget
> metadata:
>   name: default
>   namespace: longhorn-system
> spec:
>   backupTargetURL: s3://sss-k3s-dev-longhorn-backups@ap-south-1/
>   credentialSecret: longhorn-s3-secret
>   pollInterval: "300s"
> EOF
> ```
> The credential secret **must** exist and be referenced even when using IAM roles, but
> `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` must be **completely absent** from the secret
> (empty string values are treated the same as missing and will cause an error).
> This should be created automatically by Helm (via `backupTargetCredentialSecret` in values.yaml)
> but may not apply on a messy first install.

## Create Test PVC

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-test
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF

kubectl get pvc longhorn-test
# STATUS: Bound  (takes ~15 seconds)

kubectl delete pvc longhorn-test
```

## Configure Recurring Backup to S3

The Longhorn backup target is already set to the S3 bucket provisioned by Terraform.
The worker IAM role has the required `s3:PutObject/GetObject/DeleteObject` permissions.

Set up a recurring snapshot + backup via the Longhorn UI (`https://longhorn.yourdomain.com`)
or via CRDs:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: daily-backup
  namespace: longhorn-system
spec:
  cron: "0 2 * * *"     # 2am UTC daily
  task: backup
  groups:
    - default
  retain: 14             # keep 14 daily backups
  concurrency: 1
  labels:
    type: daily
EOF
```

Apply the `default` group to all PVCs with:

```bash
kubectl annotate pvc <pvc-name> recurring-job-group.longhorn.io/default=enabled
```

## Protect Longhorn UI with Basic Auth

```bash
# Generate credentials
htpasswd -nb admin <strong-password> | base64

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: longhorn-basic-auth
  namespace: longhorn-system
type: kubernetes.io/basic-auth
data:
  users: <base64-output-from-htpasswd>
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: longhorn-auth
  namespace: longhorn-system
spec:
  basicAuth:
    secret: longhorn-basic-auth
EOF

# Add middleware to the Longhorn ingress
kubectl -n longhorn-system annotate ingress longhorn-frontend \
  traefik.ingress.kubernetes.io/router.middlewares=longhorn-system-longhorn-auth@kubernetescrd
```

## Production Notes

- **`reclaimPolicy: Retain`** prevents data loss when a PVC is deleted accidentally.
  You will need to manually delete the Longhorn volume from the UI to reclaim space.
- **3 replicas with hard anti-affinity** means the cluster needs all 3 workers healthy
  to schedule new volumes. If a worker is terminated (spot), Longhorn will rebuild the
  missing replica on the remaining nodes within minutes.
- **50 GB per node** = 150 GB raw → ~50 GB usable with 3x replication. Increase
  `longhorn_disk_size` in `modules/ec2/k3s-worker/variable.tf` and apply before
  the cluster is created to change disk size.
- The worker IAM role uses the AWS EC2 instance role — no static S3 credentials needed.
