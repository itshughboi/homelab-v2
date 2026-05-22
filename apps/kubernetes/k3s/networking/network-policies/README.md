# Network Policies

Default-deny east-west isolation between namespaces. Each app namespace only accepts traffic from within itself and from the `traefik` ingress namespace. Namespaces that need to talk to each other (e.g. ArgoCD → Gitea) get explicit allow rules.

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
  kubectl apply -f allow-traefik-ingress.yaml -n "$ns"
  kubectl apply -f allow-monitoring-scrape.yaml -n "$ns"
  kubectl apply -f allow-dns.yaml -n "$ns"
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
