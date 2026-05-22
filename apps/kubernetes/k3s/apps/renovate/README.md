# Renovate Bot

Automated dependency update PRs for Docker image tags in the homelab repo. Runs as a weekly CronJob on the k3s cluster, targeting your Gitea instance.

## Overview

| | |
|---|---|
| **Image** | `renovate/renovate:38` |
| **Schedule** | Weekly, Sunday 10PM |
| **Platform** | Gitea (self-hosted) |
| **Repo** | `hughboi/homelab` |

## How It Works

1. CronJob fires on schedule
2. Renovate scans `apps/kubernetes/k3s/apps/**/deployment.yaml` for container image tags
3. Checks registries (Docker Hub, ghcr.io, etc.) for newer versions
4. Opens PRs in Gitea with changelogs and diff when updates are found
5. ArgoCD detects the merged PR and syncs the cluster

## Before You Apply

Create the Gitea PAT:
- Gitea → Settings → Applications → Generate Token
- Scopes needed: `repository` (read + write) for PR creation

```bash
kubectl create secret generic renovate-env -n renovate \
  --from-literal=RENOVATE_TOKEN=<gitea-pat> \
  --from-literal=GITHUB_COM_TOKEN=<optional-github-pat>
```

The GitHub PAT is optional but recommended — Renovate fetches changelogs from GitHub release pages for most images, and without a token it hits rate limits quickly.

## Deploy

```bash
kubectl apply -f namespace.yaml
kubectl apply -f configmap.yaml
# Create secret first (see above)
kubectl apply -f cronjob.yaml
```

## Run Immediately (Testing)

```bash
kubectl create job --from=cronjob/renovate renovate-manual -n renovate
kubectl logs -f job/renovate-manual -n renovate
```

## Config Highlights

- **Patch updates**: Auto-merged via Gitea's platformAutomerge (no review needed)
- **Minor/major**: Opens PRs for manual review
- **pgvecto-rs**: Disabled — Immich requires a pinned version
- **Authentik**: Updates batched but not auto-merged — requires changelog review
- **Dependency Dashboard**: Renovate creates a tracking issue in Gitea listing all pending updates

## Updating the Config

Edit `configmap.yaml` and re-apply. Changes take effect on the next CronJob run.
To change which repos Renovate monitors, add to the `repositories` array in `config.json`.
