# Velero — Cluster Backup & Restore

Velero backs up all Kubernetes resources (namespaces, deployments, secrets, configmaps,
PVCs) and Longhorn volume data to S3. The Terraform stack has already provisioned
the `sss-k3s-dev-velero-backups` S3 bucket and the worker IAM role has the required
S3 permissions.

## Prerequisites

- Longhorn installed (Velero uses Longhorn CSI snapshots for PV data)
- All 3 workers healthy
- Helm repos added
- `velero` CLI installed on bastion

## Install Velero CLI on Bastion

```bash
VELERO_VERSION=$(curl -s https://api.github.com/repos/vmware-tanzu/velero/releases/latest \
  | grep tag_name | cut -d'"' -f4)
curl -sL "https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz" \
  | tar xz --strip-components=1 -C /usr/local/bin velero-${VELERO_VERSION}-linux-amd64/velero
velero version --client-only
```

## Get Bucket and Region from Terraform

```bash
BUCKET=$(terraform -chdir=/path/to/sss-k3s-cluster output -raw velero_backup_bucket)
REGION="ap-south-1"
echo "Bucket: $BUCKET"
```

## values.yaml

Save as `~/velero-values.yaml`:

```yaml
# Use the AWS plugin for S3 + EC2 snapshot support
initContainers:
  - name: velero-plugin-for-aws
    image: velero/velero-plugin-for-aws:v1.11.x   # match Velero version
    imagePullPolicy: IfNotPresent
    volumeMounts:
      - mountPath: /target
        name: plugins

# IAM credentials — use ServiceAccount annotation to assume the worker role
# The worker IAM role has S3 permissions; no static credentials needed.
serviceAccount:
  server:
    annotations:
      # No annotation needed — running on EC2 instances with the worker instance profile
      # Velero will use the EC2 IMDS to get credentials automatically

credentials:
  useSecret: false   # rely on EC2 instance IAM role (node has worker profile)

configuration:
  backupStorageLocation:
    - name: default
      provider: aws
      bucket: sss-k3s-dev-velero-backups   # ← replace if cluster name differs
      config:
        region: ap-south-1
      default: true

  volumeSnapshotLocation:
    - name: default
      provider: aws
      config:
        region: ap-south-1

  # Use Longhorn CSI snapshots for PV data (preferred over EBS snapshots for portability)
  defaultVolumesToFsBackup: false   # use CSI snapshots, not file-system backup

nodeSelector:
  role: worker

resources:
  requests:
    cpu: 500m
    memory: 256Mi
  limits:
    cpu: "1"
    memory: 512Mi

# Install Velero's backup/restore CRDs
upgradeCRDs: true
```

## Install

```bash
kubectl create namespace velero

helm upgrade --install velero vmware-tanzu/velero \
  --namespace velero \
  --values ~/velero-values.yaml \
  --version 8.x \
  --wait
```

> Check latest: `helm search repo vmware-tanzu/velero --versions | head -5`

## Verify

```bash
kubectl -n velero get pods
# velero-* Running

velero backup-location get
# NAME      PROVIDER   BUCKET/PREFIX                    PHASE       ...
# default   aws        sss-k3s-dev-velero-backups       Available

velero snapshot-location get
```

## Configure Longhorn CSI Snapshot Support

Velero needs CSI snapshot CRDs and a snapshot class to back up Longhorn volumes:

```bash
# Install CSI snapshot controller CRDs (if not present)
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml

# Install the snapshot controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml

# Create a Longhorn VolumeSnapshotClass for Velero
cat <<EOF | kubectl apply -f -
kind: VolumeSnapshotClass
apiVersion: snapshot.storage.k8s.io/v1
metadata:
  name: longhorn-snapshot-class
  labels:
    velero.io/csi-volumesnapshot-class: "true"   # Velero auto-discovers this
driver: driver.longhorn.io
deletionPolicy: Delete
EOF
```

## Create a Scheduled Backup

```bash
# Back up all namespaces nightly at midnight UTC, keep 14 days
velero schedule create nightly-full \
  --schedule="0 0 * * *" \
  --ttl 336h \
  --include-namespaces '*' \
  --default-volumes-to-fs-backup=false

velero schedule get
```

## Manual Backup

```bash
# Backup everything
velero backup create manual-$(date +%Y%m%d-%H%M) \
  --include-namespaces '*' \
  --wait

velero backup get
velero backup describe manual-<name> --details
```

## Restore From Backup

**Restore to the same cluster (e.g., after disaster):**

```bash
# List available backups
velero backup get

# Restore (does not overwrite existing resources by default)
velero restore create --from-backup manual-20260306-1200 \
  --include-namespaces default,monitoring,longhorn-system \
  --wait

velero restore describe <restore-name>
velero restore logs <restore-name>
```

**Restore a single namespace:**

```bash
velero restore create restore-monitoring \
  --from-backup nightly-full-20260305000000 \
  --include-namespaces monitoring \
  --wait
```

**Restore to a new/different cluster:**

1. Deploy the new cluster with the same Terraform config
2. Install Velero with the same S3 bucket and region
3. Velero will automatically discover existing backups
4. Run `velero restore create` as above

## Verify Backup Contents

```bash
velero backup describe nightly-full-20260305000000 --details
# shows all resources backed up, any warnings/errors

# Download and inspect locally
velero backup download nightly-full-20260305000000
tar tzf nightly-full-20260305000000-data.tar.gz | head -50
```

## Production Notes

- **Do not** use `defaultVolumesToFsBackup: true` (file-system backup) for Longhorn
  volumes larger than a few GB — it streams data through the Velero pod and is slow.
  CSI snapshots are instant and consistent.
- The `sss-k3s-dev-velero-backups` bucket has a **90-day lifecycle policy** applied by
  Terraform (STANDARD_IA at 14 days, GLACIER at 60 days, delete at 90 days). Set
  `velero schedule --ttl` to match (336h = 14 days for nightly, 2160h = 90 days for weekly).
- **Test your restores regularly.** A backup that has never been tested is not a backup.
  Schedule a quarterly restore drill to a test cluster.
- The worker IAM role only has permissions for the `velero-backups` bucket. Velero
  cannot accidentally write to the etcd or Longhorn backup buckets.
