# ArgoCD

GitOps continuous delivery for the k3s cluster. ArgoCD watches your Gitea repo and automatically syncs changes to the cluster — push to `main` and ArgoCD applies it.

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

ArgoCD syncs everything in git **except** Secrets (via `ignoreDifferences` on the `/data` field). Secrets are created imperatively with `kubectl create secret` before the first sync. ArgoCD will see the Secret exists and leave it alone.

This means:
- ✅ All YAML manifests (Deployments, Services, IngressRoutes, ConfigMaps) are GitOps-managed
- ✅ New apps appear automatically when you add a directory
- ⚠️ Secrets are NOT in git — you must run the `kubectl create secret` commands in each app's README when deploying a new app

If you want fully automated secrets, consider migrating to [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) later.

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
2. Create the secret imperatively: `kubectl create secret generic ... -n <appname>`
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
