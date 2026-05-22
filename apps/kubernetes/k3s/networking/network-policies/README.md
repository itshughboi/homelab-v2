# Network Policies

Default-deny isolation in both directions. Ingress (inbound) and egress (outbound) are each denied by default — explicit allow rules grant only what each namespace legitimately needs.

**Why both directions matter:**
- Ingress-only deny stops external pods from reaching your app, but a compromised pod can still make outbound connections to C2 servers or exfiltrate data.
- Egress deny ensures a compromised pod is also blind outbound — it can't call home or reach internal services it shouldn't know about.

## Available policies

| File | Direction | Purpose |
|------|-----------|---------|
| `default-deny.yaml` | Ingress | Block all inbound. Apply to every namespace. |
| `default-deny-egress.yaml` | Egress | Block all outbound. Apply to every namespace. |
| `allow-dns.yaml` | Ingress | Allow DNS responses into pods |
| `allow-dns-egress.yaml` | Egress | Allow pods to reach kube-dns (port 53) — **required** |
| `allow-traefik-ingress.yaml` | Ingress | Allow Traefik to reach pods |
| `allow-monitoring-scrape.yaml` | Ingress | Allow Prometheus to scrape pods |
| `allow-https-egress.yaml` | Egress | Allow pods to reach external HTTPS APIs |
| `allow-internal-egress.yaml` | Egress | Allow pods to reach other cluster services |

## Two approaches

### 1. Per-app (preferred for GitOps)

Critical apps embed their own `networkpolicy.yaml` directly in their directory — ArgoCD manages them automatically. Done for: `gitea`, `authentik`, `vaultwarden`.

Add `networkpolicy.yaml` to any app directory following the same pattern:
```yaml
# default-deny + allow-traefik + allow-monitoring
# Copy from apps/gitea/networkpolicy.yaml and adjust namespace + any extra rules
```

### 2. Bulk apply (for the rest)

For apps that don't have bespoke rules, apply the templates in this directory to all namespaces at once. Run after all apps are deployed and verified:

```bash
APP_NAMESPACES=(
  authentik change-detection ezbookkeeping fasten-health file-browser
  freshrss gatus hoarder home-assistant homepage immich jellyfin
  mailrise mealie n8n netbootxyz ntfy paperless-ngx pocket-id
  prometheus-pve-exporter renovate restic romm searxng semaphore
  syncthing tube-archivist wazuh
)

for ns in "${APP_NAMESPACES[@]}"; do
  echo "Applying network policies to namespace: $ns"
  kubectl apply -f default-deny.yaml -n "$ns"
  kubectl apply -f default-deny-egress.yaml -n "$ns"
  kubectl apply -f allow-traefik-ingress.yaml -n "$ns"
  kubectl apply -f allow-monitoring-scrape.yaml -n "$ns"
  kubectl apply -f allow-dns.yaml -n "$ns"
  kubectl apply -f allow-dns-egress.yaml -n "$ns"
done

# Apps that need internet access (external APIs, webhooks, package downloads):
INTERNET_NAMESPACES=(home-assistant immich renovate n8n paperless-ngx mealie)
for ns in "${INTERNET_NAMESPACES[@]}"; do
  kubectl apply -f allow-https-egress.yaml -n "$ns"
done

# Apps that need to reach other cluster services (Prometheus, Loki, Authentik):
CLUSTER_NAMESPACES=(gitea authentik vaultwarden semaphore)
for ns in "${CLUSTER_NAMESPACES[@]}"; do
  kubectl apply -f allow-internal-egress.yaml -n "$ns"
done
```

## Important: enable DNS egress too

Without `allow-dns.yaml`, pods can't resolve any hostnames after default-deny is applied. Always apply `allow-dns.yaml` to every namespace.

```bash
cat allow-dns.yaml
```

## Testing isolation

```bash
# From namespace gatus, try to reach n8n — should fail (timeout) with policies in place
kubectl run -it --rm test --image=busybox:1.36 --restart=Never -n gatus -- \
  wget -T 3 -q http://n8n.n8n.svc.cluster.local 2>&1
# Expected: "wget: download timed out" or connection refused

# From traefik namespace, should succeed
kubectl run -it --rm test --image=busybox:1.36 --restart=Never -n traefik -- \
  wget -T 3 -q http://gitea.gitea.svc.cluster.local:3000 2>&1
# Expected: HTML response
```

## Debugging a blocked connection

```bash
# Check which policies are in place for a namespace
kubectl get networkpolicies -n <namespace>

# Describe a policy to see its selectors
kubectl describe networkpolicy default-deny-ingress -n <namespace>

# If a pod can't reach something it should, add an explicit allow rule.
# If you need a temporary bypass for debugging:
kubectl delete networkpolicy default-deny-ingress -n <namespace>  # re-apply when done
```
