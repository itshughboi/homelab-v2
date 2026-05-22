# Glances

**URL:** http://10.10.10.10:61208 (localhost only — not behind Traefik)
**Docs:** https://nicolargo.github.io/glances/

System monitoring dashboard. Shows real-time CPU, memory, disk, network, processes, and Docker container stats for the host. Accessible only from localhost (port bound to `127.0.0.1`).

## Stack

Single container. Requires `pid: host` and `privileged: true` to see host-level process information — these cannot be removed without losing visibility into host metrics.

## Access

The web UI is on port `61208` but bound to `127.0.0.1` only, so it's not accessible remotely. To reach it from another machine, use an SSH tunnel:

```sh
ssh -L 61208:127.0.0.1:61208 hughboi@10.10.10.10
# then open http://localhost:61208 in your browser
```

## Config

The config file lives at `./glances.conf` in the service directory (mounted at `/glances/conf/glances.conf`). The container starts in web server mode via `-w` in `GLANCES_OPT`.

Useful config sections:
- `[cpu]`, `[mem]`, `[disk]` — thresholds for colour coding (green/yellow/red)
- `[docker]` — Docker container monitoring (via docker.sock)
- `[process]` — filter which processes are shown

## Volumes

| Mount | Purpose |
|---|---|
| `./glances.conf` | Thresholds and display config |
| `/var/run/docker.sock:ro` | Docker container stats |

## Why Privileged?

Glances needs `pid: host` to enumerate all host processes (not just in-container ones) and `privileged: true` to access certain host-level metrics like network interface stats and disk I/O at the hardware level. Without these, the process list only shows container-internal processes and some metrics are unavailable.

## Upgrade Notes

- No persistent data volume — all state is in the config file and the running host.
- Check the [Glances changelog](https://github.com/nicolargo/glances/releases) before upgrading — config schema options occasionally change between major versions.

## Troubleshooting

**Docker containers not showing:**
- The docker.sock mount must be present. Verify with `docker exec glances ls /var/run/docker.sock`

**Only seeing container processes, not host processes:**
- Requires `pid: host` in compose. If this was removed, add it back and recreate the container.
