# cert-manager — TLS Certificate Management

cert-manager issues and renews TLS certificates automatically via Let's Encrypt.
The k3s server IAM role already has the required Route53 permissions for DNS-01
challenges (see `modules/iam/main.tf`).

## Prerequisites

- Traefik installed and running (see `01-traefik.md`)
- Route53 hosted zone ID (set in `terraform.tfvars` as `route53_hosted_zone_id`)
- Helm repos added

## Install cert-manager

```bash
kubectl create namespace cert-manager

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set crds.enabled=true \
  --set global.leaderElection.namespace=cert-manager \
  --version v1.19.4 \
  --wait
```

> Check latest: `helm search repo jetstack/cert-manager --versions | head -5`

## Verify Installation

```bash
kubectl -n cert-manager get pods
# cert-manager-*            Running
# cert-manager-cainjector-* Running
# cert-manager-webhook-*    Running

# Install cmctl — moved to its own repo since cert-manager v1.12
# (no longer shipped with cert-manager releases)
# Named kubectl-cert_manager so kubectl's plugin system maps it to 'kubectl cert-manager'
curl -fsSL https://github.com/cert-manager/cmctl/releases/latest/download/cmctl_linux_amd64 -o cmctl
chmod +x cmctl
sudo mv cmctl /usr/local/bin/kubectl-cert_manager

kubectl cert-manager check api
# The cert-manager API is ready
```

## ClusterIssuer — Let's Encrypt via Route53 DNS-01

The k3s server IAM role has Route53 permissions and the EC2 instance uses that role
automatically — no AWS credentials need to be stored in Kubernetes secrets.

```bash
# Get your hosted zone ID
ZONE_ID=$(terraform -chdir=/path/to/sss-k3s-cluster output -raw route53_hosted_zone_id 2>/dev/null || echo "YOUR_ZONE_ID")
REGION="ap-south-1"
```

Save as `~/cert-manager-issuers.yaml` and apply:

```yaml
---
# Staging issuer — test first, avoids Let's Encrypt rate limits
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: your@email.com          # ← replace
    privateKeySecretRef:
      name: letsencrypt-staging-key
    solvers:
      - dns01:
          route53:
            region: ap-south-1
            hostedZoneID: YOUR_ZONE_ID    # ← replace
            # No accessKeyID/secretAccessKey — uses EC2 instance IAM role
---
# Production issuer — use after staging works
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your@email.com          # ← replace
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - dns01:
          route53:
            region: ap-south-1
            hostedZoneID: YOUR_ZONE_ID    # ← replace
```

```bash
kubectl apply -f ~/cert-manager-issuers.yaml
kubectl get clusterissuer
# letsencrypt-staging   True
# letsencrypt-prod      True
```

## Test Certificate (Staging)

```bash
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: test-cert
  namespace: default
spec:
  secretName: test-cert-tls
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
  dnsNames:
    - test.yourdomain.com
EOF

# Watch it issue (takes ~30–90 seconds)
kubectl get certificate test-cert -w
# READY column should go True

# Inspect if stuck
kubectl describe certificate test-cert
kubectl describe certificaterequest
kubectl describe order
kubectl describe challenge
```

Once staging works, switch `issuerRef.name` to `letsencrypt-prod`.

## Clean Up Test Certificate

```bash
kubectl delete certificate test-cert
kubectl delete secret test-cert-tls
```

## Using cert-manager with Traefik Ingress

Option A — annotation on an Ingress resource:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  rules:
    - host: myapp.yourdomain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: myapp-svc
                port:
                  number: 80
  tls:
    - hosts:
        - myapp.yourdomain.com
      secretName: myapp-tls
```

Option B — create a Certificate resource explicitly and reference the secret in a Traefik IngressRoute.

## Wildcard Certificate

For a single cert covering all subdomains:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-cert
  namespace: traefik        # same namespace as Traefik so it can read the secret
spec:
  secretName: wildcard-yourdomain-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - "*.yourdomain.com"
    - "yourdomain.com"
```

Reference in IngressRoute:
```yaml
tls:
  secretName: wildcard-yourdomain-tls
```

## Production Notes

- **DNS-01 is the correct solver** for this cluster. HTTP-01 requires the domain to resolve
  to the node, which only works after the cert is issued — a chicken-and-egg problem.
  With DNS-01, cert-manager writes a TXT record to Route53 and Let's Encrypt verifies it
  without needing HTTP access.
- **Rate limits**: Let's Encrypt prod allows 5 duplicate certs per week and 50 per domain.
  Always test with `letsencrypt-staging` first.
- Using the EC2 instance IAM role for Route53 (no static credentials) is the correct
  production pattern — credentials cannot leak or expire.


## Which one should you use?

**Option A** for most apps — it's concise and automatic

**Option B** when you need Traefik-specific features like middlewares (auth, rate limiting, redirects), path rewrites, or TCP routing

For Rancher, Longhorn UI, Grafana, etc. you'll mostly use Option A since those Helm charts generate standard Ingress resources and just need ingressClassName: traefik plus the annotation set.