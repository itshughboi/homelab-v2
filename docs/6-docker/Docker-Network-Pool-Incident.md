# Docker Network Address Pool Incident — dock-prod, 2026-07-16

> [!CAUTION]
> Widening Docker's `default-address-pools` to fix "all predefined address pools have been fully
> subnetted" took down **every container on dock-prod** for several minutes, because the first
> chosen pool range collided with a pre-existing legacy Docker network. Root cause: picking a
> "looks unused" subnet without actually enumerating every subnet already in use first.

## What happened

Deploying `hoarder` via `sops-deploy` failed at the `docker compose up` step:

```
Error response from daemon: all predefined address pools have been fully subnetted
```

dock-prod runs ~30+ Compose projects, most creating their own bridge network. Docker's default
address pool (a fixed set of `/16`s across `172.18.0.0`–`172.31.0.0`, plus `/20`s across
`192.168.0.0/16`) had been fully consumed over time — no new networks could be created. This part
was expected and non-destructive (no container was created, nothing running was affected) — see
[docs/6-docker/index.md](index.md#important-rules) for the steady-state fix (prune orphaned
networks, widen the pool).

**The first widening attempt made things worse.** `172.20.0.0/17` was chosen — it looked
reasonable (256+ new networks, clear of the `172.16.20.0/24` Torrent VLAN) — and written to
`/etc/docker/daemon.json`. Restarting Docker to apply it failed outright:

```
failed to start daemon: Error initializing network controller: error creating default "bridge"
network: all predefined address pools have been fully subnetted
```

Docker couldn't even recreate its own default `bridge` network on startup, because a
**pre-existing legacy network** (`br-5c752290c900`, one of the original `/16`-sized default
networks, sitting on `172.20.0.1/16`) directly overlapped the new `172.20.0.0/17` pool. Docker
won't allocate an overlapping subnet, so the new pool config itself was invalid — and with
`dockerd` refused to start, **every container on the host was down**, including Traefik, Gitea's
runner, and everything else, for the duration of the incident.

## Diagnosis Sequence

With `dockerd` down, normal tools (`docker network inspect`, `docker network ls`) don't work —
they require a running daemon. Bridge interfaces persist at the kernel level independent of
`dockerd`, so read them directly instead:

```sh
sudo journalctl -u docker.service --no-pager -n 50
# → showed the exact failure: "error creating default \"bridge\" network: all predefined
#   address pools have been fully subnetted"

ip -4 addr show | grep -A1 "br-\|docker0"
# → lists every Docker bridge interface and its assigned subnet directly from the kernel,
#   e.g.: br-5c752290c900: inet 172.20.0.1/16 ...
```

Cross-referencing the full list of existing bridge subnets against the `172.16.0.0/12` and
`192.168.0.0/16` ranges showed:
- **Every** `/16` from `172.18.0.0` to `172.31.0.0` was already claimed by a legacy network —
  only `172.16.0.0/16` (unsafe — contains the Torrent VLAN) and `172.17.0.0/16` were free.
- `192.168.0.0/16` was almost entirely carved into contiguous `/20` blocks by Docker's own
  historical allocations — only a few fragmented `/24`-ish gaps remained, not enough headroom.

## Recovery Path

`172.17.0.0/16` (256 `/24` networks) was confirmed to overlap **nothing** — not the Torrent VLAN,
not any existing Docker network:

```sh
sudo tee /etc/docker/daemon.json > /dev/null <<'JSONEOF'
{
  "default-address-pools": [
    { "base": "172.17.0.0/16", "size": 24 }
  ]
}
JSONEOF
sudo systemctl restart docker
sudo systemctl status docker.service --no-pager
```

Docker started cleanly (`Active: active (running)`), and every previously-running container
reconnected automatically — Docker preserves container state independent of the daemon restart,
it just needed the daemon back up to re-attach networking. Verified with
`docker ps --format '{{.Names}}\t{{.Status}}'`: everything came back except `promtail`, which was
already independently crash-looping before this incident (see
[`apps/docker/promgraftail/README.md`](../docker/promgraftail/README.md) — unrelated, still
unresolved).

Total outage: roughly 6 minutes, from the failed restart to Docker coming back up healthy on the
corrected config.

## Lessons / Prevention

- **Never pick a new address pool base by inspection/guessing.** Enumerate every subnet actually
  in use first (`ip -4 addr show | grep -A1 'br-'`, works with `dockerd` up *or* down) and
  confirm zero overlap before writing `daemon.json`. "Looks free" is not the same as "is free" —
  Docker's own historical `/16` allocations aren't visible from `docker network ls` alone if
  you're reasoning about ranges rather than checking each one.
- **A `daemon.json` mistake can prevent Docker from starting at all**, not just fail to create
  the *new* network you wanted — Docker recreates its own default `bridge` network on every
  startup, so a bad pool config is a full-daemon-down bug, not a scoped one.
- Widening the pool only affects **new** networks going forward — restarting Docker does not
  renumber or disrupt any existing network's subnet.
- Restarting Docker briefly drops all containers' networking (not the containers themselves) —
  do this during a low-traffic window regardless of how confident the config looks.
- Current pool: `172.17.0.0/16` (256 `/24`s), in `/etc/docker/daemon.json`. If it needs widening
  again, re-run the enumeration step above — don't assume the "free" ranges from this incident
  are still free; new networks have been created against `172.17.0.0/16` since.
