# 6. Docker

Docker services split across two hosts: **Athena** (management stack) and **dock-prod** (production services). Both are VMs on Proxmox, both provisioned from Template 9999 via Terraform.

> ▸ **Build order:** [BUILD.md](../BUILD.md) **Phase 6 (Docker)** — after Git handoff (Phase 5); before k3s.

---

## Hardening TODO (from the per-app audit)

`apps/docker/` is live production — apply these in code, then `docker compose up -d <svc>`. The
overall stack is strong (100% pinned images, `no-new-privileges` everywhere, Loki logging).

**Quick wins**
- [ ] **gatus + homepage** — DNS `10.10.10.9` → `10.10.10.8` (Bind9 runs on Athena `.8`; `.9` is bogus). traefik is already on `.8`; the stragglers are gatus (`compose.yaml` + `config/config.yaml`), homepage (`compose.yaml`), and the bind9 zone `db.hughboi.vip` self-record.
- [ ] **bind9** — move off the `_beta` image tag (foundational DNS shouldn't run a beta).

**Medium**
- [ ] **mem_limit** on the memory-heavy apps — `jellyfin`, `immich`, `home-assistant` (prevent one OOM from taking neighbors on the shared host). Only 6/35 services set limits today.
- [ ] **glances** + **promgraftail** run **`privileged: true`** — scope down (Glances API mode; Telegraf with specific caps instead of full privileged).
- [ ] **gitea runner** mounts `docker.sock` **RW** = root on dock-prod (audit **C3**) — restrict the runner to this repo + require PR approval for first-time contributors.
- [ ] **vaultwarden** is publicly reachable and holds everything (audit **H4**) — front with Authentik forward-auth + IP-restrict `/admin`; set `SIGNUPS_ALLOWED=false`.
- [ ] **paths** — 20/35 compose files hardcode `/home/hughboi/...`; standardize on `${CODE_ROOT}`/`${DATA_ROOT}` (adguard already does it) so a rebuild on a different path is one var change.

**Low**
- [ ] **glances** lacks `no-new-privileges` (it's also privileged) — review whether it needs host access at all.
- [ ] **vaultwarden** `apparmor:unconfined` — confirm it's actually required.

> Not on this list because they're already correct: image pinning (100%), Loki logging,
> `no-new-privileges` (all but glances), gitea Postgres healthcheck + `pids_limit`, CrowdSec
> bouncer, file-based secrets (traefik CF token). netbootxyz was relocated to `sunset/`.

---

## The Two Docker Hosts

| Host | IP | Purpose |
| --- | --- | --- |
| Athena | 10.10.10.8 | Management: **Gitea, Semaphore, Bind9** |
| dock-prod | 10.10.10.10 | Production: **Traefik** + everything user-facing (AdGuard, CrowdSec, Vaultwarden, ntfy, Mailrise, apps) |

Athena runs first (Phase 8) because dock-prod depends on Athena's DNS and Git server. Once Semaphore is running on Athena, all remaining service startups can be triggered from the Semaphore UI.

> Traefik (the reverse proxy for `*.hughboi.cc`) runs **only on dock-prod** — it fronts the
> Athena-hosted services (Gitea, Semaphore) over the network. Athena itself does not run Traefik.
>
> **How this actually works:** Traefik's Docker-label routing (`traefik.http.routers.*` labels)
> only discovers containers on the *same host* as Traefik — it can't see across hosts. So
> Athena-hosted services are **not** labeled; they publish their ports directly
> (`gitea: ports: ["3000:3000"]`) and get a **static route** in Traefik's file provider instead:
> [`apps/docker/traefik/data/config.yml`](../../apps/docker/traefik/data/config.yml) has a
> hand-written `http.routers`/`http.services` block pointing at `10.10.10.8:<port>` for each one.
> If you add a new Athena-hosted service that needs a `*.hughboi.cc` hostname, it goes there,
> not in that service's own compose labels — Docker labels on an Athena compose file are silently
> inert since Traefik never sees them.

---

## Important Rules

> [!IMPORTANT]
> **`apps/docker/` is live production.** Every compose file in that folder is running on dock-prod. Read it for reference — do not modify files here without explicit intent.

**Traefik binding:** Traefik on dock-prod is explicitly bound to `10.10.10.10`, not `0.0.0.0`. This is intentional — prevents Docker from publishing ports to the wrong interface or bypassing the VLAN firewall.

**Docker and iptables:** Docker bypasses iptables by default. For host-level restrictions, use the `DOCKER-USER` chain. Never use `--network=host` unless it's the only option (Bind9 on Athena is the deliberate exception).

**Storage backplane (VLAN 40):** dock-prod is dual-homed — a second NIC on VLAN 40 at `10.10.40.10` (no gateway, MTU 9000) carries NFS to TrueNAS (`10.10.40.5`) over jumbo frames. Point NFS mounts at `10.10.40.5` (storage IP), **not** `10.10.10.5` (management). NIC in [`dock-prod.tf`](../../terraform/proxmox/dock-prod.tf); setup in [Virtual Interfaces](../2-proxmox/pve/Virtual%20Interfaces.md). Intra-zone in the firewall — no new rule needed.

**NFS mounts before compose up:** Tube Archivist and Restic require their TrueNAS NFS mounts to exist before `docker compose up`. If the mount is missing, the container starts with an empty directory and data loss follows silently. Always verify: `mount | grep nfs`

**Wazuh startup time:** The Wazuh OpenSearch indexer takes 2-3 minutes to initialize. Expect connection errors in the dashboard for a few minutes after `docker compose up` — this is normal.

**Immich version pinning:** `immich/home` and `immich/eros` must run the same `IMMICH_VERSION` in their `.env` files. Mismatched versions corrupt the database.

---

## Athena — Management Stack

Athena runs **Bind9, Gitea, and Semaphore** (no Traefik — that's on dock-prod). Start in order:

```sh
# 1. DNS — everything resolves through this
cd apps/docker/bind9 && docker compose up -d

# 2. Git server + runner
cd apps/docker/gitea && docker compose up -d

# 3. Ansible UI (from here, retire the laptop)
cd apps/docker/semaphore && docker compose up -d
# Set up in Semaphore UI: SSH key, Gitea repo, inventory path
```

---

## dock-prod — Production Services

Bind9 (DNS, on Athena) must be up first. Traefik comes up first here, since everything
user-facing is fronted by it.

```sh
# 1. Reverse proxy + TLS — fill in the Cloudflare token first
echo "your-cloudflare-token" > ${DATA_ROOT}/traefik/cf_api_token.txt
chmod 600 ${DATA_ROOT}/traefik/cf_api_token.txt
cd apps/docker/traefik && docker compose up -d

# 2. DNS filtering (LAN ad-block for WiFi/guest)
cd apps/docker/adguard && docker compose up -d

# 3. Security middleware
cd apps/docker/crowdsec && docker compose up -d
docker exec crowdsec cscli bouncers add traefik-bouncer
# Copy the API key → traefik/.env as CROWDSEC_BOUNCER_API_KEY, then:
docker restart traefik

# 4. Notifications (so subsequent playbooks can alert you)
cd apps/docker/ntfy && docker compose up -d
cd apps/docker/mailrise && docker compose up -d

# 5. Password manager
cd apps/docker/vaultwarden && docker compose up -d

# 6. Monitoring (up before you need to debug anything)
cd apps/docker/promgraftail && docker compose up -d

# 7. Security SIEM
cd apps/docker/wazuh && docker compose up -d   # takes 2-3 min to start

# 8. Identity / SSO
cd apps/docker/pocket-id && docker compose up -d

# 9. Automation
cd apps/docker/n8n && docker compose up -d

# 10. Media (NFS mounts must be present first)
sudo mount -a && mount | grep nfs   # verify before starting
cd apps/docker/jellyfin && docker compose up -d
cd apps/docker/immich/home && docker compose up -d
cd apps/docker/immich/eros && docker compose up -d   # GPU transcoding instance

# 11. NFS-dependent services
cd apps/docker/tube-archivist && docker compose up -d
cd apps/docker/restic && docker compose up -d

# 12. Everything else
for svc in paperless-ngx romm mealie freshrss hoarder homepage \
           gatus change-detection searxng home-assistant \
           diun syncthing file-browser \
           fasten-health ezbookkeeping unifi; do
  cd apps/docker/$svc && docker compose up -d && cd -
done
```

---

## Full Service List

| Service | Host | URL | Purpose |
| --- | --- | --- | --- |
| Gitea | Athena | https://gitea.hughboi.cc | Self-hosted Git |
| Semaphore | Athena | https://semaphore.hughboi.cc | Ansible Web UI + scheduler |
| Bind9 | Athena | 10.10.10.8:53 | Authoritative LAN DNS |
| Traefik | dock-prod | https://traefik.hughboi.cc | Reverse proxy + TLS for `*.hughboi.cc` (fronts all services, incl. Athena's) |
| AdGuard (LAN) | dock-prod | https://adguard.hughboi.cc | DNS resolver + ad blocker for LAN |
| Vaultwarden | dock-prod | https://vault.hughboi.cc | Self-hosted Bitwarden |
| CrowdSec | dock-prod | — | Intrusion detection |
| Portainer | dock-prod | https://portainer.hughboi.cc | Container management UI |
| Wazuh | dock-prod | https://wazuh.hughboi.cc | SIEM / security monitoring |
| n8n | dock-prod | https://n8n.hughboi.cc | Automation workflows |
| Pocket ID | dock-prod | https://pocket.hughboi.cc | OIDC provider (SSO) |
| Jellyfin | dock-prod | https://jellyfin.hughboi.cc | Media server |
| Immich | dock-prod | https://immich.hughboi.cc | Photo management |
| Tube Archivist | dock-prod | https://tube.hughboi.cc | YouTube archiver |
| RomM | dock-prod | https://romm.hughboi.cc | Retro gaming library |
| Paperless-ngx | dock-prod | https://paperless.hughboi.cc | Document management |
| Mealie | dock-prod | https://mealie.hughboi.cc | Recipe manager |
| Freshrss | dock-prod | https://rss.hughboi.cc | RSS reader |
| Hoarder | dock-prod | https://hoarder.hughboi.cc | Bookmark manager |
| Homepage | dock-prod | https://home.hughboi.cc | Dashboard |
| Gatus | dock-prod | https://status.hughboi.cc | Uptime monitoring |
| Home Assistant | dock-prod | https://ha.hughboi.cc | Home automation |
| Restic | dock-prod | — | Backup agent |
| ntfy | dock-prod | https://ntfy.hughboi.cc | Push notifications |
| Mailrise | dock-prod | — | Email → ntfy bridge |
| Syncthing | dock-prod | https://sync.hughboi.cc | File sync |
| File Browser | dock-prod | https://files.hughboi.cc | Web file manager |
| UniFi Controller | dock-prod | https://unifi.hughboi.cc | Network controller |
| Diun | dock-prod | — | Docker image update notifier |
| Fasten Health | dock-prod | https://health.hughboi.cc | Health records |
| EzBookkeeping | dock-prod | https://money.hughboi.cc | Finance tracker |
| Change Detection | dock-prod | https://cd.hughboi.cc | Website change monitor |
| SearXNG | dock-prod | https://search.hughboi.cc | Private search engine |
| Glances | dock-prod | — | Host metrics dashboard/API (**status TBD** — pending dock-prod's future) |
| promgraftail | dock-prod | — | dock-prod monitoring stack: Grafana + Loki + Prometheus/Telegraf (**status TBD**; see [7-k3s/Monitoring](../7-k3s/Monitoring.md)) |

---

## Adding a New Docker Service

1. Create `apps/docker/<name>/compose.yaml` and `.env.example`
2. Store secrets in Vaultwarden
3. Copy `.env.example` → `.env`, fill in values — never commit `.env`
4. `docker compose up -d`
5. Add the service to the `docker/compose-health` Ansible inventory

---

## Scheduled Docker Maintenance (Semaphore)

| Playbook | Schedule | Purpose |
| --- | --- | --- |
| `docker/compose-health` | Daily | Catch containers that crashed overnight |
| `docker/volume-backup` | Weekly | Named volume backup to TrueNAS |
| `docker/postgres-maintenance` | Monthly | VACUUM ANALYZE on all Postgres instances |
| `ubuntu/ssl-cert-expiry` | Daily | Know before users see cert warnings |
