Fleet disk-usage snapshot → one consolidated ntfy message.

## What it does

Answers "where are we sitting disk-wise across all nodes?" — runs `df` on every
host in the inventory (4 Proxmox nodes + Athena + dock-prod + the 9 k3s VMs),
then sends **one** ntfy notification to `https://ntfy.hughboi.cc/homelab` listing
every real filesystem, **sorted fullest-first** so whatever needs attention is at
the top. Filesystems at/over 85% get a ⚠️ marker and bump the message priority.

This is a **capacity** snapshot (how full), not a SMART/drive-health check — that's
the separate [`disk-health`](../disk-health/) playbook (temperature, reallocated
sectors, failing drives). Different concern, kept separate on purpose.

Motivated by an incident where Athena's root filesystem silently filled to 100%
(a 3.9 GB `~/.vscode-server` cache on a 14 GB disk), which broke Gitea and a
package install before anyone noticed. This gives a cheap on-demand "are we OK?"
without needing the Prometheus/Alertmanager stack up.

## Usage

```sh
ansible-playbook -i inventory.yaml main.yaml
```

**As a Semaphore Task Template:** point it at this playbook, no survey vars needed.
Run on demand, or schedule it (daily/weekly) for a regular heartbeat. Reaches
Athena over SSH like every other host — Semaphore's `homelab-athena` key must be in
the Athena host's authorized_keys (see
[../../docker/compose-control/README.md](../../docker/compose-control/README.md)).

## Notes / limitations

- **Snapshot, not alerting.** It reports whatever's there when you run it; it does
  not watch continuously. For "warn me the moment a disk crosses 85% at 3am,"
  that's a Prometheus alert rule (node_exporter exports `node_filesystem_avail_bytes`)
  — a better fit for continuous monitoring, tracked for the monitoring-stack work.
  This playbook is the quick manual/scheduled check, complementary to that.
- **Excludes pseudo-filesystems** (tmpfs, devtmpfs, overlay, squashfs) via `df -x`
  so it only reports disks that can actually fill.
- **Mount points with spaces would mis-parse** (the row is split on whitespace).
  None of this fleet's mounts have spaces, so it's a non-issue here — just don't
  assume it handles arbitrary exotic mount names.
- **`warn_at_pct`** (default 85) only controls the ⚠️ marker and message
  priority/title; the report always lists every filesystem regardless.
