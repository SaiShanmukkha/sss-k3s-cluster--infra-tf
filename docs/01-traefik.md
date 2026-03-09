# Traefik — Ingress Controller

Traefik is deliberately **disabled** in the k3s install flags (`--disable traefik`) so it can be
installed via Helm with full control over NodePorts and configuration. HAProxy on the ingress
nodes is already pre-configured to forward :30080 and :30443 to worker nodes.

## Prerequisites

- Cluster accessible from bastion (`kubectl get nodes` returns all 6 nodes Ready)
- Helm repos added (see `00-cluster-access.md`)
- DNS wildcard record pointing at the ingress floating EIP

## Create Namespace

```bash
kubectl create namespace traefik
```

## values.yaml

Save as `~/traefik-values.yaml` on bastion:

```yaml
# Deploy only on worker nodes (role=worker label)
nodeSelector:
  role: worker

# Run one replica per worker node for HA
deployment:
  replicas: 3

# Use NodePort — HAProxy on ingress nodes forwards :30080 and :30443 here
service:
  type: NodePort

ports:
  web:
    nodePort: 30080
  websecure:
    nodePort: 30443

# Global HTTPS redirect
ingressRoute:
  dashboard:
    enabled: false   # Expose via IngressRoute below instead

# Persist Traefik's own ACME data (only needed if using Traefik ACME, not cert-manager)
persistence:
  enabled: false   # cert-manager handles TLS; Traefik doesn't need its own ACME store

# Enable the Kubernetes Ingress provider (for standard Ingress resources)
providers:
  kubernetesIngress:
    enabled: true
    publishedService:
      enabled: true

# Allow cross-namespace IngressRoute references
ingressClass:
  enabled: true
  isDefaultClass: true

# Redirect HTTP → HTTPS globally
additionalArguments:
  - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
  - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
  - "--entrypoints.web.http.redirections.entrypoint.permanent=true"

# Resource limits for production
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi

# Prometheus metrics
metrics:
  prometheus:
    enabled: true
    addEntryPointsLabels: true
    addServicesLabels: true

logs:
  general:
    level: WARN
  access:
    enabled: true
```

## Install

```bash
helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --values ~/traefik-values.yaml \
  --version 32.x \
  --wait
```

> Check latest stable version: `helm search repo traefik/traefik --versions | head -5`

## Verify

```bash
kubectl -n traefik get pods -o wide
# All 3 pods should be Running, one per worker node

kubectl -n traefik get svc
# traefik   NodePort   ...   80:30080/TCP,443:30443/TCP
```

Test the HTTP→HTTPS redirect:

```bash
curl -I http://<ingress_eip>
# HTTP/1.1 301 Moved Permanently
# Location: https://...
```

## Expose Traefik Dashboard (Optional)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: traefik-dashboard
  namespace: traefik
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(\`traefik.yourdomain.com\`)
      kind: Rule
      services:
        - name: api@internal
          kind: TraefikService
  tls:
    certResolver: letsencrypt    # set up in cert-manager doc
EOF
```

## Production Notes

- **3 replicas** — one per worker AZ. If a worker spot instance is interrupted, the other two keep serving traffic.
- **NodePort is intentional** — HAProxy load-balances across all 3 workers. No AWS Load Balancer required (cost saving).
- **Do not** enable `service.type: LoadBalancer`. It would try to provision an AWS NLB which bypasses HAProxy entirely.
- Traefik stores no state — rolling restarts are safe.
