# Monitoring Stack — Prometheus, Grafana, Alertmanager

`kube-prometheus-stack` installs the full observability stack: Prometheus (metrics collection),
Grafana (dashboards), Alertmanager (notifications), and pre-built Kubernetes dashboards.

## Prerequisites

- Longhorn installed and set as default StorageClass (metrics need persistent storage)
- Traefik installed (for Grafana and Prometheus web UIs)
- cert-manager with `letsencrypt-prod` ClusterIssuer
- DNS records: `grafana.yourdomain.com`, `prometheus.yourdomain.com`, `alertmanager.yourdomain.com`
- Helm repos added

## Create Namespace

```bash
kubectl create namespace monitoring
```

## values.yaml

Save as `~/monitoring-values.yaml`:

```yaml
# ── Prometheus ────────────────────────────────────────────────────────────────
prometheus:
  prometheusSpec:
    # Run only on workers
    nodeSelector:
      role: worker
    # 15-day retention, stored on Longhorn
    retention: 15d
    retentionSize: 40GB
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi
    # Scrape all ServiceMonitors/PodMonitors across all namespaces
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: "2"
        memory: 3Gi
    # Expose via Traefik (internal use only — secure with basic auth)
  ingress:
    enabled: true
    ingressClassName: traefik
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    hosts:
      - prometheus.yourdomain.com   # ← replace
    tls:
      - secretName: prometheus-tls
        hosts:
          - prometheus.yourdomain.com

# ── Alertmanager ──────────────────────────────────────────────────────────────
alertmanager:
  alertmanagerSpec:
    nodeSelector:
      role: worker
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: longhorn
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi
    resources:
      requests:
        cpu: 50m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
  ingress:
    enabled: true
    ingressClassName: traefik
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    hosts:
      - alertmanager.yourdomain.com   # ← replace
    tls:
      - secretName: alertmanager-tls
        hosts:
          - alertmanager.yourdomain.com

# ── Grafana ───────────────────────────────────────────────────────────────────
grafana:
  nodeSelector:
    role: worker
  persistence:
    enabled: true
    storageClassName: longhorn
    size: 10Gi
  adminPassword: "<strong-grafana-admin-password>"   # ← replace
  ingress:
    enabled: true
    ingressClassName: traefik
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    hosts:
      - grafana.yourdomain.com    # ← replace
    tls:
      - secretName: grafana-tls
        hosts:
          - grafana.yourdomain.com
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
        - name: default
          folder: ""
          type: file
          disableDeletion: false
          options:
            path: /var/lib/grafana/dashboards
  # Pre-load community dashboards
  dashboards:
    default:
      kubernetes-cluster:
        gnetId: 7249
        revision: 1
        datasource: Prometheus
      kubernetes-nodes:
        gnetId: 1860    # Node Exporter full
        revision: 37
        datasource: Prometheus
      traefik:
        gnetId: 17347
        revision: 9
        datasource: Prometheus
      longhorn:
        gnetId: 16888
        revision: 9
        datasource: Prometheus
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

# ── Node Exporter ─────────────────────────────────────────────────────────────
nodeExporter:
  enabled: true   # runs on every node (DaemonSet), including servers

# ── kube-state-metrics ────────────────────────────────────────────────────────
kubeStateMetrics:
  enabled: true

# ── Operator resource sizing ──────────────────────────────────────────────────
prometheusOperator:
  nodeSelector:
    role: worker
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 256Mi
```

## Install

```bash
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values ~/monitoring-values.yaml \
  --version 69.x \
  --wait --timeout 15m
```

> Check latest: `helm search repo prometheus-community/kube-prometheus-stack --versions | head -5`

## Verify

```bash
kubectl -n monitoring get pods
# All pods Running

kubectl -n monitoring get pvc
# prometheus-db, alertmanager-db, grafana — all Bound on longhorn

kubectl -n monitoring get ingress
# grafana, prometheus, alertmanager — all with TLS
```

## Configure Alertmanager — Slack Notifications

Create a Slack webhook secret and configure routing:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-slack
  namespace: monitoring
type: Opaque
stringData:
  slack-webhook-url: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
EOF
```

Add to `monitoring-values.yaml` under `alertmanager.config`:

```yaml
alertmanager:
  config:
    global:
      slack_api_url_file: /etc/alertmanager/secrets/alertmanager-slack/slack-webhook-url
    route:
      group_by: ['alertname', 'namespace']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      receiver: slack-critical
      routes:
        - match:
            severity: critical
          receiver: slack-critical
        - match:
            severity: warning
          receiver: slack-warnings
    receivers:
      - name: slack-critical
        slack_configs:
          - channel: '#k8s-alerts-critical'
            title: '[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}'
            text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
            send_resolved: true
      - name: slack-warnings
        slack_configs:
          - channel: '#k8s-alerts'
            title: '[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}'
            send_resolved: true
    inhibit_rules:
      - source_match:
          severity: critical
        target_match:
          severity: warning
        equal: ['alertname', 'namespace']
  alertmanagerSpec:
    secrets:
      - alertmanager-slack
```

Apply: `helm upgrade ... --reuse-values -f ~/monitoring-values.yaml`

## Key Dashboards

After logging into Grafana (`https://grafana.yourdomain.com`, user: `admin`):

| Dashboard | ID | What it shows |
|---|---|---|
| Node Exporter Full | 1860 | CPU, memory, disk, network per host |
| Kubernetes Cluster | 7249 | Namespace-level resource usage |
| Traefik | 17347 | Request rate, latency, error rate per service |
| Longhorn | 16888 | Volume health, IOPS, replication lag |
| etcd | 3070 | etcd leader elections, commit latency (critical for control plane) |

## Critical Alerts to Know

These fire by default from the kube-prometheus-stack rules:

| Alert | Meaning |
|---|---|
| `KubeNodeNotReady` | A node left the cluster (spot reclamation?) |
| `KubePVCPendingTooLong` | PVC not binding — Longhorn issue |
| `EtcdMembersDown` | etcd quorum threat — immediate action |
| `PrometheusTargetMissing` | A scrape target disappeared |
| `NodeDiskRunningFull` | Worker disk at >85% — increase EBS volume |
| `CPUThrottlingHigh` | Pod hitting CPU limits |

## Production Notes

- **50 Gi for Prometheus** is sufficient for a 6-node cluster with 15-day retention.
  Monitor actual usage in Grafana → Prometheus dashboard → TSDB stats.
- **All 3 ingresses** (Grafana, Prometheus, Alertmanager) should be protected with
  network-level controls or basic auth Traefik middleware — Prometheus and Alertmanager
  have no built-in authentication.
- **Do not skip etcd dashboard** — etcd health is the single most critical metric for
  a k3s HA control plane. Set up an alert on `etcd_server_has_leader == 0`.
- **Worker spot interruptions** will cause brief gaps in node-exporter metrics. This is
  expected — the node will rejoin after the spot instance is restarted (persistent spot).
