# Traefik

Ingress controller and reverse proxy for the k3s cluster. Every `*.hughboi.vip` domain routes through Traefik.

## Overview

| | |
|---|---|
| **Chart** | `traefik/traefik` |
| **Replicas** | 3 (worker nodes only) |
| **External IP** | `10.10.30.75` (MetalLB) |
| **TLS** | Wildcard `*.hughboi.vip` via cert-manager + Let's Encrypt (Cloudflare DNS-01) |
| **Security** | CrowdSec bouncer plugin on both `web` and `websecure` entrypoints |
| **Backends** | `insecureSkipVerify: true` — Traefik trusts self-signed certs on upstream pods |

## Directory Layout

```
helm/traefik/
├── values.yaml                         # Helm values for traefik chart
├── default-headers.yaml                # Middleware: security response headers
├── dashboard/
│   ├── ingress.yaml                    # IngressRoute to the Traefik dashboard
│   ├── middleware.yaml                 # BasicAuth middleware for dashboard
│   └── secret-dashboard.yaml          # Hashed credentials (htpasswd format)
├── cert-manager/
│   ├── values.yaml                     # cert-manager Helm values
│   ├── issuers/
│   │   ├── letsencrypt-production.yaml # ClusterIssuer using Cloudflare DNS-01
│   │   └── secret-cf-token.yaml        # Cloudflare API token secret
│   └── certificates/production/
│       └── hughboi-production.yaml     # Certificate: *.hughboi.vip + root
manifest/
└── bouncer-middleware.yaml             # CrowdSec IngressRouteTCPMiddleware
helm/crowdsec/values.yaml               # CrowdSec Helm values
helm/reflector/values.yaml              # Reflector Helm values
```

## How TLS Works

1. **cert-manager** uses a `ClusterIssuer` that proves domain ownership via Cloudflare DNS-01 (no exposed ports required).
2. cert-manager issues a wildcard cert `*.hughboi.vip` and stores it as Secret `hughboi-tls` in the `traefik` namespace.
3. **Reflector** (emberstack) watches that secret and mirrors it automatically into every namespace listed in the `secretTemplate` annotations on the Certificate.
4. Each app's `IngressRoute` references `hughboi-tls` from its own namespace.

Current reflection targets in [cert-manager/certificates/production/hughboi-production.yaml](helm/traefik/cert-manager/certificates/production/hughboi-production.yaml):
```
monitoring, vaultwarden, tube-archivist, searxng, syncthing, unifi
```

**When you add a new app:** add its namespace to that annotation and Reflector will push the secret in automatically within ~30s of namespace creation.

## Deploy Order

```bash
# 1. cert-manager
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace \
  --set installCRDs=true \
  -f helm/traefik/cert-manager/values.yaml

# 2. Reflector — NOW GITOPS-MANAGED via argocd/apps/reflector-app.yaml (chart 10.0.46).
#    Skip during rebuild; ArgoCD installs it automatically once root-app is applied.

# 3. Traefik
helm repo add traefik https://traefik.github.io/charts
helm install traefik traefik/traefik \
  -n traefik --create-namespace \
  -f helm/traefik/values.yaml

# 4. CrowdSec — NOW GITOPS-MANAGED via argocd/apps/crowdsec-app.yaml (chart 0.24.0).
#    Skip during rebuild; ArgoCD installs it automatically once root-app is applied.

# 5. Issuers and certificate
kubectl apply -f helm/traefik/cert-manager/issuers/secret-cf-token.yaml
kubectl apply -f helm/traefik/cert-manager/issuers/letsencrypt-production.yaml
kubectl apply -f helm/traefik/cert-manager/certificates/production/hughboi-production.yaml

# 6. Middlewares and dashboard
kubectl apply -f helm/traefik/default-headers.yaml
kubectl apply -f helm/traefik/dashboard/
kubectl apply -f manifest/bouncer-middleware.yaml
```

## Verify Certificate

```bash
kubectl get certificate -n traefik
kubectl describe certificate hughboi -n traefik
# should show: Ready = True
```

## Adding a New App's IngressRoute

All IngressRoutes follow this pattern:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: myapp
  namespace: myapp
spec:
  entryPoints: [websecure]
  routes:
    - match: Host(`myapp.hughboi.vip`)
      kind: Rule
      services:
        - name: myapp
          port: 8080
  tls:
    secretName: hughboi-tls
```

Add `myapp` to the Reflector annotation on the certificate, then apply the IngressRoute.

## Notes

- HTTP → HTTPS redirect is configured in `values.yaml` via `ports.web.redirections`.
- `externalTrafficPolicy: Local` is required for CrowdSec to see real client IPs.
- The CrowdSec bouncer plugin is loaded at Traefik startup — if CrowdSec is down, Traefik still starts but the bouncer will log errors until CrowdSec recovers.
- `pullPolicy: Always` is set — consider pinning to a digest for production stability.
