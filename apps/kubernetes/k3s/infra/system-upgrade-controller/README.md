# System Upgrade Controller

Automates k3s version upgrades across cluster nodes using declarative `Plan` resources. Replaces manually SSH-ing into each node to run the k3s install script.

## How It Works

1. You apply a `Plan` pointing to a k3s release channel (`stable`, `latest`, or a pinned version)
2. The controller cordons a node, drains workloads, upgrades the k3s binary, and uncordons
3. Server (master) nodes upgrade first; agent (worker/longhorn) nodes wait via the `prepare` step

## Install

```bash
# Install the CRDs and controller
kubectl apply -f https://github.com/rancher/system-upgrade-controller/releases/latest/download/crd.yaml
kubectl apply -f https://github.com/rancher/system-upgrade-controller/releases/latest/download/system-upgrade-controller.yaml

# Apply the Plans
kubectl apply -f plans.yaml
```

The controller runs in the `system-upgrade` namespace (created by the upstream manifest).

## Upgrade Channels

| Channel | Meaning |
|---------|---------|
| `stable` | Latest stable k3s (recommended) |
| `latest` | Cutting edge — may be RC |
| `v1.30` | Pins to a specific minor version |

To pin to a specific version instead of a channel, replace `channel:` with `version:`:
```yaml
version: v1.30.5+k3s1
```

## Monitoring an Upgrade

```bash
# Watch plans
kubectl get plans -n system-upgrade
# Watch the upgrade jobs as they run
kubectl get jobs -n system-upgrade -w
# Logs from a specific upgrade job
kubectl logs -n system-upgrade job/<plan>-<node>-<hash>
```

## Rollback

System Upgrade Controller doesn't support automatic rollback. If an upgrade fails:
1. Check logs on the failed node
2. SSH to the node and re-run the previous k3s install script manually:
   ```bash
   curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.29.x+k3s1 sh -
   ```

## Maintenance Windows

To control when upgrades happen, you can pair this with a node label strategy: only label nodes during a maintenance window, and set the Plan's `nodeSelector` to match that label. Remove the label outside the window to pause upgrades.

## Notes

- Plans cordons nodes before upgrading — Longhorn replicas will rebuild after the node comes back. Ensure you have sufficient replicas (3x replication) before enabling upgrades.
- `concurrency: 1` means one node at a time. Safe for a 3-master HA setup.
- The stable channel polls periodically — upgrades don't happen instantly when a new k3s version drops.
