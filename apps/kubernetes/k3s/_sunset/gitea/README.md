# Gitea (in-cluster) — SUNSET

> [!WARNING] Not deployed — Gitea lives on Athena, not in the cluster
> This in-cluster Gitea was the original plan for the GitOps source, but it creates a
> bootstrap cycle (ArgoCD needs Gitea before the cluster exists). The decided architecture:
> **Gitea runs on Athena (`10.10.10.8:3000`)** and ArgoCD/Renovate/Terraform all pull it by
> direct IP — see [argocd/README](../../argocd/README.md). This directory was moved to
> `_sunset/` (outside the ApplicationSet's `apps/*` glob) so ArgoCD never deploys it.
> Kept as reference in case an in-cluster **mirror** is ever wanted (it would be a replica,
> never the source of truth).

Self-hosted Git service — formerly planned as the GitOps source of truth for ArgoCD.

## Overview

| | |
|---|---|
| **Image** | `gitea/gitea:1.26` |
| **Domain** | `gitea.hughboi.vip` |
| **HTTP Port** | 3000 |
| **SSH Port** | 2222 (LoadBalancer) |
| **Containers** | gitea + PostgreSQL |
| **Storage** | 20Gi PVC (git data) + 10Gi PVC (postgres) |

## Services

| Service | Type | Purpose |
|---------|------|---------|
| `gitea` | ClusterIP | HTTP API + web UI → Traefik |
| `gitea-ssh` | LoadBalancer | Git SSH → direct client access |

## Before You Apply

```bash
kubectl create secret generic gitea-env -n gitea \
  --from-literal=POSTGRES_DB=gitea \
  --from-literal=POSTGRES_USER=gitea \
  --from-literal=POSTGRES_PASSWORD=<password>
```

## Deploy Order

```bash
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f secret.yaml
kubectl apply -f postgres.yaml
kubectl rollout status deployment/gitea-postgres -n gitea
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
kubectl apply -f ingressroute.yaml
```

After deploy, get the SSH LoadBalancer IP:
```bash
kubectl get svc gitea-ssh -n gitea
```

Configure your SSH client to use port 2222:
```
# ~/.ssh/config
Host gitea.hughboi.vip
  Port 2222
  User git
```

## Migrating from Docker

```bash
kubectl scale deployment gitea -n gitea --replicas=0
kubectl run copy --image=alpine -n gitea --restart=Never -- sleep 3600
kubectl cp /home/hughboi/data/gitea/. gitea/copy:/data/
kubectl delete pod copy -n gitea
kubectl scale deployment gitea -n gitea --replicas=1
```

The Postgres data migration is separate — use `pg_dump` on the source and `pg_restore` on the target.

## Gitea Actions Runner

The Docker setup included `gitea/act_runner` which requires Docker socket access. In k8s you have two options:

**Option A: Keep the runner on the Docker host** — simpler, runner can still call back to `gitea.hughboi.vip`. Register with the runner token from Gitea UI.

**Option B: Gitea Actions Runner in k8s** — requires either Docker-in-Docker (DinD) or [Kaniko](https://github.com/GoogleContainerTools/kaniko) for builds. Considerably more complex. Defer until needed.

## ArgoCD Integration

Once Gitea is running, register the repo in ArgoCD:
```bash
argocd repo add http://gitea.gitea.svc.cluster.local:3000/hughboi/homelab.git \
  --username hughboi \
  --password <gitea-token>
```

## Notes

- `GITEA__server__SSH_PORT=2222` tells Gitea to display port 2222 in clone URLs. The LoadBalancer maps external 2222 → internal 22.
- `strategy: Recreate` required for ReadWriteOnce PVCs.
- Add `gitea` to the Reflector annotation on the TLS certificate.
