# Portainer

**URL:** https://portainer.hughboi.cc
**Docs:** https://docs.portainer.io/

Docker management UI. Browse containers, volumes, networks, images, logs, and exec into containers from a browser. Useful for quick inspection without SSH.

> [!WARNING]
> **Slated for decommission, pending a Grafana replacement.** Now that most Docker services
> deploy via `ansible/playbooks/docker/sops-deploy/` (encrypted secrets, driven from Semaphore),
> Portainer's redeploy/recreate actions are actively dangerous for any SOPS-migrated service —
> the decrypted `.env` only exists on disk briefly during a `sops-deploy` run and is deleted
> afterward, so a Portainer-triggered container **recreation** (not a plain restart — Compose
> "redeploy"/stop+remove+up) would start the container with blank secrets instead of failing
> loudly. **Never use Portainer to redeploy, recreate, or edit the compose stack of any migrated
> service — only `sops-deploy` should do that.** A plain `docker restart` (via Portainer or the
> CLI) is still safe, since it reuses the already-running container's existing environment.
>
> Plan: enable cAdvisor (already in `apps/docker/promgraftail/compose.yaml`, currently commented
> out) and build a Grafana dashboard for container status/resource usage — Portainer's other two
> real uses (console/exec access, restart button) are covered by a `dexec()` shell helper on
> dock-prod and `docker restart <name>` respectively. Once the dashboard's proven out, remove
> Portainer entirely — one fewer path to accidentally deploy something outside the SOPS/Semaphore
> pipeline.

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
