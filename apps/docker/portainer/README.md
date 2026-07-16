# Portainer

**URL:** https://portainer.hughboi.cc
**Docs:** https://docs.portainer.io/

Docker management UI. Browse containers, volumes, networks, images, logs, and exec into containers from a browser. Useful for quick inspection without SSH.

> [!WARNING]
> **Never redeploy/recreate a SOPS-migrated service through Portainer.** Now that most Docker
> services deploy via `ansible/playbooks/docker/sops-deploy/` (encrypted secrets, driven from
> Semaphore), the decrypted `.env` only exists on disk briefly during a `sops-deploy` run and is
> deleted afterward. A Portainer-triggered container **recreation** (not a plain restart — Compose
> "redeploy"/stop+remove+up) would start the container with blank secrets instead of failing
> loudly. **Only `sops-deploy` should redeploy, recreate, or edit the compose stack of a migrated
> service.** A plain `docker restart` (via Portainer or the CLI) is still safe, since it reuses
> the already-running container's existing environment.
>
> Otherwise, Portainer stays — it's still genuinely useful for image/volume/network browsing +
> pruning, quick console access, and managing non-SOPS hosts via Portainer agents (staging boxes,
> anything not on the encrypted-secrets pipeline, where the risk above doesn't apply). A `dexec()`
> shell helper was added to dock-prod as a lighter console-access option
> (see `docs/6-docker/index.md`), but that's a convenience, not a replacement — no plan to remove
> Portainer.

## Stack

Single container. Mounts the Docker socket at `/run/docker.sock` (read-write — Portainer needs write access to start, stop, and manage containers).

## Volumes

| Mount | Purpose |
|---|---|
| `/run/docker.sock` | Docker socket — full management access |
| `portainer-data` (named volume) | Portainer DB — users, settings, saved templates |

## First Run

1. `docker compose up -d`
2. Navigate to https://portainer.hughboi.cc
3. Create the admin account (prompted on first visit — do this quickly, Portainer locks the setup endpoint after 5 minutes)
4. Select **Docker Standalone** as the environment

## Security Note

Portainer has full Docker socket access (read-write). Anyone who can log into Portainer can do anything on the host that Docker can do. Keep the admin password strong and consider restricting access to VPN-only if exposing to the internet.

## Upgrade Notes

- Settings and user accounts are in the `portainer-data` named volume. This survives upgrades.
- Portainer CE has a built-in update button in the UI — it works but it's safer to update via compose so the image tag stays pinned.
- Before upgrading, verify the new version supports the current DB schema (Portainer sometimes requires sequential upgrades — don't skip major versions).

## Troubleshooting

**"Setup already started" error on first visit:**
- The 5-minute setup window expired. Delete and recreate the container (the `portainer-data` volume is safe to keep):
```sh
docker stop portainer && docker rm portainer
docker compose up -d
```

**Can't see containers from another Docker host:**
- Portainer CE manages only the local Docker daemon via the mounted socket. For remote hosts, add them as **Environments** in the Portainer UI using the Portainer agent or TCP.

**Lost admin password:**
1. Stop Portainer
2. Delete the `portainer-data` volume (this wipes all settings and users)
3. Restart — you'll get the first-run setup again
```sh
docker stop portainer
docker volume rm portainer_portainer-data
docker compose up -d
```
