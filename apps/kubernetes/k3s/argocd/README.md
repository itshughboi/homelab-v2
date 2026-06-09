# ArgoCD

GitOps continuous delivery for the k3s cluster. ArgoCD watches your Gitea repo and automatically syncs changes to the cluster — push to `main` and ArgoCD applies it.

> [!IMPORTANT] Why the repo URL is a direct IP, not `gitea.hughboi.cc`
> The `Application`/`ApplicationSet` manifests pull from **`http://10.10.10.8:3000`** (the Athena
> Gitea by **direct IP**), *not* the `gitea.hughboi.cc` hostname. This is deliberate:
> - **Traefik-independent:** if dock-prod's Traefik is down, ArgoCD still pulls. (`gitea.hughboi.cc`
>   routes through that Traefik — using it would couple GitOps to dock-prod being up.)
> - **DNS-independent:** an IP needs no Bind9 lookup, so a DNS outage doesn't block syncs either.
> - The only remaining hard dependency is **Athena itself** (where Gitea lives). Break-glass: point
>   the repo URL at the **GitHub mirror**.
>
> Requires a firewall allow `K3S → 10.10.10.8:3000` (k3s→MGMT is deny-by-default) — see
> [Firewall Rules](../../../../docs/1-networking/Unifi/Firewall/Rules.md#k3s-10103024). Full
> failure-mode analysis: [Dependency-Map](../../../../docs/Dependency-Map.md#failure-modes--if-x-is-down).
>
> ⚠️ Gitea currently runs on **dock-prod**; this URL assumes the planned move to **Athena**. Until
> then, use `10.10.10.10:3000` or move Gitea first.

## Overview

| | |
|---|---|
| **Chart** | `argo/argo-cd` |
| **Domain** | `argocd.hughboi.vip` |
| **Port** | 80 (ArgoCD serves HTTP; TLS terminated at Traefik) |
| **Gitea repo** | `http://gitea.gitea.svc.cluster.local:3000/hughboi/homelab.git` |

## Architecture

```
Git push to main
       │
       ▼
  ArgoCD (polling every 3min or via webhook)
       │
       ├── root Application           watches argocd/apps/
       │       ├── apps-appset.yaml   → ApplicationSet (auto-discovers apps/*)
       │       └── monitoring-app.yaml → monitoring/
       │
       └── ApplicationSet             watches apps/kubernetes/k3s/apps/*
               └── creates one Application per subdirectory (auto-discovers new apps)
```

The **App of Apps** pattern means you only need to register the `root` Application manually. Everything else is self-managing — add a new app directory in git, and ArgoCD creates and syncs it automatically.

## Secret Strategy

**Primary: Sealed Secrets** — secrets are encrypted and committed to Git. ArgoCD applies `SealedSecret` resources; the sealed-secrets controller decrypts them into real `Secret` objects in-cluster. Full cluster rebuilds need no manual secret re-entry.

**Reference: Imperative secrets** — documented below as fallback/break-glass. Useful during initial bootstrap before the sealed-secrets controller is running.

This means:
- ✅ All YAML manifests (Deployments, Services, IngressRoutes, ConfigMaps, SealedSecrets) are GitOps-managed
- ✅ New apps appear automatically when you add a directory
- ✅ Secrets live in git encrypted — rebuild = `helm install` + `argocd app sync`, no manual steps
- ⚠️ Sealed Secrets controller must be installed **before** ArgoCD first syncs (see bootstrap order below)

### Sealed Secrets Workflow (Primary)

The sealed-secrets controller must be running before you seal anything. Install it once during cluster bootstrap — see [`infra/sealed-secrets/`](../infra/sealed-secrets/) for the full install + key backup procedure.

```bash
# 1. Create secret as a dry-run (never apply this directly)
kubectl create secret generic my-app-secret -n my-app \
  --from-literal=api-key=<value> \
  --from-literal=db-password=<value> \
  --dry-run=client -o yaml \
  | kubeseal --format yaml > apps/kubernetes/k3s/apps/my-app/sealed-secret.yaml

# 2. Commit and push
git add apps/kubernetes/k3s/apps/my-app/sealed-secret.yaml
git commit -m "feat: add my-app sealed secret"
git push

# ArgoCD applies the SealedSecret → controller decrypts → Secret appears in cluster
```

> [!IMPORTANT]
> **Back up the controller key immediately after install.** Without it, all sealed secrets are permanently unreadable if the cluster is rebuilt.
> ```bash
> kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml \
>   > ~/sealed-secrets-master.key
> # Store in Vaultwarden — NEVER commit to git
> ```

### Imperative Secrets (Reference / Break-Glass)

Use this when the sealed-secrets controller isn't running yet (early bootstrap) or for one-off emergency access.

```bash
kubectl create secret generic my-app-secret \
  -n my-app \
  --from-literal=api-key=<value> \
  --from-literal=db-password=<value>
```

Each app that uses imperative secrets has a `secret.yaml` in its directory containing only comments — no plaintext values:

```yaml
# Create this secret imperatively before ArgoCD syncs:
# kubectl create secret generic my-app-secret \
#   -n my-app \
#   --from-literal=api-key=<value>
#
# Get the value from Vaultwarden: homelab / my-app / api-key
```

ArgoCD ignores existing Secrets (via `ignoreDifferences` on `/data`) so it won't overwrite or delete imperatively-created secrets.

### SOPS + Age vs Sealed Secrets

These are complementary tools operating at different layers — not alternatives:

| Tool | Layer | What it encrypts | Who decrypts |
|------|-------|------------------|--------------|
| SOPS + Age | Ansible / Terraform | `.tfvars`, `secrets.yaml` for provisioning | Athena at runtime |
| Sealed Secrets | Kubernetes / ArgoCD | k8s `Secret` objects | In-cluster controller |

## Install

### 1. Install ArgoCD via Helm

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  -n argocd --create-namespace \
  -f install/values.yaml
kubectl rollout status deployment/argocd-server -n argocd
```

### 2. Apply the IngressRoute

Wait until the `argocd` TLS secret is reflected (30s after namespace is created):
```bash
kubectl apply -f install/ingressroute.yaml
```

### 3. Get the initial admin password

```bash
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

Log in at `https://argocd.hughboi.vip` with user `admin` and the password above. Change it immediately.

### 4. Add your Gitea repo

```bash
argocd login argocd.hughboi.vip --username admin

# If Gitea is public or using a token:
argocd repo add http://gitea.gitea.svc.cluster.local:3000/hughboi/homelab.git \
  --username hughboi \
  --password <gitea-token>
```

Or add the repo via the ArgoCD UI: `Settings → Repositories → Connect Repo`.

### 5. Bootstrap the root Application

This is the only thing you apply manually — it manages everything else:

```bash
kubectl apply -f apps/root-app.yaml
```

ArgoCD will immediately start syncing:
- `apps-appset.yaml` → creates Applications for every directory in `apps/kubernetes/k3s/apps/`
- `monitoring-app.yaml` → syncs the monitoring stack

## Adding a New App

1. Create `apps/kubernetes/k3s/apps/<appname>/` with your manifests
2. Seal any secrets: `kubectl create secret generic ... --dry-run=client -o yaml | kubeseal --format yaml > sealed-secret.yaml`
3. Push to git
4. ArgoCD auto-discovers the new directory and creates an Application for it within ~3 minutes

## Sync Policies

| Policy | Setting |
|--------|---------|
| Auto-sync | ✅ Enabled |
| Prune | ✅ Removes resources deleted from git |
| Self-heal | ✅ Reverts manual `kubectl apply` changes |
| Retry | 3 attempts with exponential backoff |

**Self-heal** means if you `kubectl apply` something directly, ArgoCD will revert it within minutes. This is intentional — the cluster state should always match git. For emergency changes, either disable auto-sync temporarily in the UI or push to git.

## Webhook (Optional)

Instead of ArgoCD polling every 3 minutes, configure a Gitea webhook for instant syncs:

In Gitea: `Settings → Webhooks → Add Webhook`
- Payload URL: `https://argocd.hughboi.vip/api/webhook`
- Content type: `application/json`
- Secret: Generate with `openssl rand -hex 20` and set `webhook.github.secret` in Helm values

## Upgrading ArgoCD

```bash
helm upgrade argocd argo/argo-cd \
  -n argocd \
  -f install/values.yaml \
  --version <new-version>
```

## Notes

- The IngressRoute uses `port: 80` (not 443) because `--insecure` is set in values.yaml — ArgoCD serves HTTP and Traefik handles TLS.
- The Gitea URL uses the internal cluster address (`gitea.gitea.svc.cluster.local`) assuming Gitea is deployed to k8s. If Gitea is still on Docker, use `http://10.10.10.10:3000` or the external URL.
- Add `argocd` to the Reflector annotation on the TLS certificate.
