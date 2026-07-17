# diun — Docker Image Update Notifier

> [!NOTE] Sunset 2026-07-17
> Removed from dock-prod — the notifications went unused and were more
> annoying than useful in practice. Replaced by **Renovate**
> (`renovate.json`), which already watches `apps/docker/*/compose.yaml` and
> opens PRs for new image versions with sensible per-service automerge
> rules, matching the desired workflow of "review/approve a PR, then deploy"
> rather than a live notification stream. See
> [issue #45](https://gitea.hughboi.cc/hughboi/homelab/issues/45) for the
> remaining gap (PR merge doesn't yet auto-trigger a deploy) and
> [docs/5-security/Security-Audit-2026-05.md](../../../docs/5-security/Security-Audit-2026-05.md)
> for the original docker.sock-mount tradeoff that first raised
> "Diun vs Renovate" as a question.

Docs: https://crazymax.dev/diun/

Diun watches all running containers on the host (via docker.sock) and sends a notification whenever an upstream image tag has a newer digest available. It does **not** pull or restart anything — it only notifies.

## Access

No web UI. Notifications go to:
- **Discord** — webhook configured via `DIUN_NOTIF_DISCORD_WEBHOOKURL`
- **ntfy** — pushes to `https://ntfy.hughboi.cc`, topic `diun`

## Schedule

| Event | When |
|---|---|
| Startup check | On container start (`DIUN_WATCH_RUNONSTARTUP=true`) |
| Recurring check | Sundays at 20:00 with ±30s jitter (`0 20 * * 0`) |
| Worker threads | 20 parallel image checks |

## Network Layout

No custom network. Diun only needs access to the Docker socket and the internet (to reach registries and ntfy).

## Volumes

| Mount | Purpose |
|---|---|
| `data` (named volume) | Diun's database — tracks known image digests |
| `/var/run/docker.sock:ro` | Reads running container list to know what to watch |

## Environment Variables

| Variable | Purpose |
|---|---|
| `DIUN_NOTIF_DISCORD_WEBHOOKURL` | Discord webhook URL — set in `.env` |
| `DIUN_NOTIF_NTFY_ENDPOINT` | ntfy server base URL |
| `DIUN_NOTIF_NTFY_TOPIC` | ntfy topic (`diun`) |
| `DIUN_PROVIDERS_DOCKER_WATCHBYDEFAULT` | Watch all containers by default (`true`) |

Override per-container with the `diun.enable=false` label to suppress notifications for a specific container.

## First Run

No setup required. On first start diun scans all containers, builds its digest database, and sends an initial notification for each image it learns about. Subsequent runs only notify on changes.

## Upgrade Notes

- Diun's database is in the `data` named volume. It survives image upgrades.
- After pinning to a new image tag in compose, diun will notify about itself on next run — expected behaviour.
- Check the [release notes](https://github.com/crazy-max/diun/releases) for breaking config changes before upgrading.

## Troubleshooting

**No notifications arriving:**
1. Check container logs: `docker logs diun`
2. Verify the Discord webhook URL is valid — test with a curl POST
3. Verify ntfy is reachable from the container: `docker exec diun wget -qO- https://ntfy.hughboi.cc/diun`

**Notifications arriving for every image every run:**
- The `data` volume may have been deleted or corrupted. Diun treats unknown digests as new.
