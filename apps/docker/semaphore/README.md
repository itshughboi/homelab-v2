# Semaphore

**URL:** https://semaphore.hughboi.cc
**Docs:** https://docs.semaphoreui.com/

Web UI for running Ansible playbooks. Used to schedule and trigger automation tasks across the homelab without SSH-ing into machines manually — backups, updates, provisioning, maintenance.

## Stack

Two containers:

| Container | Role |
|---|---|
| `semaphore` | Web UI + Ansible runner |
| `semaphore-mysql` | MySQL 8.4 — playbook definitions, task history, inventory |

## Network Layout

Semaphore runs on Athena, not dock-prod — Traefik (on dock-prod) can't discover it via
Docker labels across hosts, so it's routed via a static entry in Traefik's file provider
(`apps/docker/traefik/data/config.yml`) pointing at `10.10.10.8:3001`, same pattern as
Gitea. See [6-docker/index.md](../../../docs/6-docker/index.md) for the full explanation.

- `semaphore` network: app and MySQL only — **not** `internal: true` (that setting blocks
  `ports:` publishing to the host, not just internet egress — see the Gitea compose file's
  comment for how we found this out)
- App publishes port `3001:3000` on the host (`3001` to avoid clashing with Gitea's `3000`
  on the same box)

## Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `/home/hughboi/data/semaphore/inventory/` | `/inventory:ro` | Ansible inventory files |
| `/home/hughboi/data/semaphore/authorized-keys/` | `/authorized-keys:ro` | SSH keys for Ansible to use |
| `/home/hughboi/data/semaphore/config/` | `/etc/semaphore:rw` | Semaphore config and state |

## Key Environment Variables (`.env`)

| Variable | Purpose |
|---|---|
| `MYSQL_DATABASE` / `MYSQL_USER` / `MYSQL_PASSWORD` | MySQL connection |
| `SEMAPHORE_ADMIN_PASSWORD` | Admin account password |
| `SEMAPHORE_ADMIN_EMAIL` | Admin account email |
| `SEMAPHORE_ADMIN_NAME` | Admin display name |
| `SEMAPHORE_ACCESS_KEY_ENCRYPTION` | Key for encrypting stored SSH/vault passwords — **back this up** |
| `UID` / `GID` | Run as this user — **must be `1001:0`**, not the usual `1000:1000` Docker convention. The `semaphoreui/semaphore` image's built-in user is UID 1001 (`/etc/passwd` inside the image), and `/tmp/semaphore` is created at image-build time owned by that UID. Running as `1000:1000` gets a valid-but-wrong user that can't write there — `mkdir /tmp/semaphore/project_1: permission denied` at task-run time, not at container start. |

---

## Installation
1. docker compose up
2. Create user // probably need to do it from the container
```
semaphore user add --admin --login hughboi --name hughboi --email info@hughboi.cc --passwo
rd CHANGEME
```

3. Add templates
    - Update
        - apt upgrade & restart
    - Maintenance
        - Check diskspace and send notification if running low
        - Provision VM's
    - Installation
        - Install docker
        - apt update
    - Configuration
        - ssh-copy
    - Deployment
4. Do the following
- Define an inventory (list of IP -> Hosts)
- Secure Authentication
- Create Playbooks
- Git

5. Add SSH Key in keystore
6. Create Inventory and use DNS or IP
7. Create repository
- Point this to my Git Repository
- Access Key is only used if I ned to do ssh rather than HTTPS or if it's private repo
8. Add environment
- For now just put in {}


