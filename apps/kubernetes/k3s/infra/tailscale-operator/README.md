# Tailscale Operator

Exposes Kubernetes Services directly on your Tailnet without punching holes in your firewall or exposing anything to the public internet. Useful for accessing the cluster remotely (Grafana, ArgoCD, Longhorn UI) over Tailscale without going through Traefik.

## Use Cases for This Homelab

| Use case | How |
|----------|-----|
| Remote access to Grafana/ArgoCD | Annotate Service with `tailscale.com/expose: "true"` |
| Access cluster from phone/laptop | Tailscale client + operator creates a proxy node per service |
| No-internet-required access | Works even when `hughboi.cc` DNS or Let's Encrypt is unreachable |
| Secure admin interfaces | Longhorn UI, Kubernetes dashboard — never exposed to public Traefik |

## Prerequisites

- Active Tailscale account (free tier works for homelab)
- Tailscale auth key (reusable, tagged): Tailscale admin → Settings → Auth keys → Generate key (tag: `k8s-operator`)

## Install (Helm)

```bash
helm repo add tailscale https://pkgs.tailscale.com/helmcharts
helm repo update

# Create the operator credentials secret
kubectl create namespace tailscale
kubectl create secret generic operator-oauth \
  --namespace tailscale \
  --from-literal=client_id=<tailscale-oauth-client-id> \
  --from-literal=client_secret=<tailscale-oauth-client-secret>

# Install
helm install tailscale-operator tailscale/tailscale-operator \
  --namespace tailscale \
  --set oauth.clientId="$(kubectl get secret operator-oauth -n tailscale -o jsonpath='{.data.client_id}' | base64 -d)" \
  --set oauth.clientSecret="$(kubectl get secret operator-oauth -n tailscale -o jsonpath='{.data.client_secret}' | base64 -d)"
```

Create the OAuth client in Tailscale Admin → Settings → OAuth clients (not an auth key). Grant scopes: `devices:write`, `auth_keys`.

## Exposing a Service

Add the annotation to any Service and the operator creates a Tailscale proxy node:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: monitoring
  annotations:
    tailscale.com/expose: "true"
    tailscale.com/hostname: "homelab-grafana"  # appears as this in Tailnet
spec:
  ...
```

After a minute, `homelab-grafana` appears in your Tailnet and is reachable at `http://homelab-grafana` (or via MagicDNS `homelab-grafana.tail<id>.ts.net`).

## Tailscale Ingress (Alternative to Per-Service Annotations)

For more control, use `Ingress` resources with the `ingressClassName: tailscale`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ts
  namespace: monitoring
spec:
  ingressClassName: tailscale
  rules:
    - host: homelab-grafana
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 3000
  tls:
    - hosts:
        - homelab-grafana
```

Tailscale issues its own TLS cert via Let's Encrypt for `*.ts.net` hostnames — no cert-manager needed for Tailscale-exposed services.

## Services Worth Exposing via Tailscale

- `grafana` (monitoring) — cluster observability
- `argocd-server` (argocd) — GitOps control
- Longhorn UI — storage management (LoadBalancer at 10.10.30.50, but Tailscale gives remote access)
- `kubernetes` API server — kubectl from outside the network

## Notes

- Each exposed Service creates a new node in your Tailnet using an auth key. Keep the Tailscale device list tidy — remove old nodes when decommissioning services.
- Tailscale ACLs let you restrict which Tailnet devices can reach which k8s-exposed services. Useful if you share your Tailnet with other users.
- The operator requires outbound internet access from the cluster to Tailscale's control plane. Works fine behind NAT.
