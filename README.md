# Homelab

Self-hosted infrastructure running on Proxmox, managed with IaC. All user services run behind Traefik with Let's Encrypt TLS.

> [!IMPORTANT] Current state (2026-07)
> **Most user-facing services still run on Docker (`dock-prod`) today.** The k3s cluster is live
> on pve-srv-2/3/4, but migration of individual services is ongoing. `apps/kubernetes/k3s/`
> holds real manifest work, but having a manifest doesn't mean a service is actually running on
> that platform. Don't treat a service's presence in `apps/kubernetes/k3s/apps/` as evidence
> it's live on k3s — check `apps/docker/` and the service's own README for what's actually
> deployed where.

---

## Principles

**Everything is code.** Network config, VM provisioning, k3s manifests, DNS records — all live in Git.

**Separation of planes.** Management never mixes with storage or workload traffic via VLANs. A compromised container can't pivot to management or storage.

**GitOps over manual.** Push to Git → automation applies it, where automation exists yet (Semaphore for Ansible/Docker; ArgoCD for k3s).

**Secrets never touch Git unencrypted.** SOPS + Age is used for Docker/provisioning secrets. Sealed Secrets is for k3s.

---

## Architecture (today)

```text
Proxmox Cluster (pve-srv-1/2/3/4)

pve-srv-1 → dock-prod (10.10.10.10)
  Docker host — Traefik (*.hughboi.cc)

pve-srv-1 → Athena (10.10.10.8)
  Management: Gitea, Semaphore, Bind9 (canonical DNS)

pve-srv-1 → PBS (10.10.10.6)
  Proxmox Backup Server

pve-srv-1 → Tailscale gateway (10.10.80.10)
  Subnet router / remote access

pve-srv-1 → Monitoring stack (promgraftail — Prometheus, Grafana, Loki)
  Runs on dock-prod today; candidate for its own dedicated node/k3s move later

pve-srv-1 → TrueNAS
  NFS: media, backups, documents

pve-srv-2/3/4 → k3s cluster
  Masters: 10.10.30.1-3 (VIP 10.10.30.30)
  Workers: 10.10.30.11-13, Longhorn: 10.10.30.51-53
  Same domain (hughboi.cc) — per-service DNS record
  points at whichever Traefik currently serves it
```

---

## Repository Layout

```text
homelab/
├── apps/
│   ├── docker/              # What's actually running today — ~36 services on dock-prod
│   └── kubernetes/k3s/      # k3s manifests — cluster is live, migration ongoing
│       ├── infra/           # kube-vip, MetalLB, Longhorn, system-upgrade-controller
│       ├── networking/      # Traefik, cert-manager, CrowdSec, AdGuard
│       ├── monitoring/      # kube-prometheus-stack, Loki, Alloy, Alertmanager
│       ├── argocd/          # ArgoCD install + App of Apps
│       └── apps/            # 29 services with manifests prepared, most not yet deployed
├── ansible/                 # OS provisioning, k3s install, Docker host setup
├── terraform/proxmox/       # VM provisioning (bpg/proxmox provider)
├── packer/                  # Ubuntu cloud-init template for Proxmox
├── bootstrap/                # Node install tooling (Ventoy, answer-server) — provisioning-time only
└── docs/                    # Architecture notes, numbered setup guides
```

---

**Docker Services/`dock-prod`, with real reasons:**

| Service | Why it stays on docker |
|---|---|
| Jellyfin | GPU transcoding — Intel Arc A380 is passed through on `dock-prod`. k3s nodes only have AMD Radeon iGPUs, benchmarked as a real downgrade for concurrent 4K/HDR transcoding. Revisit once `dock-prod`'s hardware is upgraded and the Arc A380 is retired. |
| Immich | Real photo libraries are large and TrueNAS-hosted; the k3s manifest uses a 100Gi Longhorn PVC for the library itself (not NFS passthrough), so moving means migrating real data into Longhorn — a deliberate future project, not a simple redeploy. |
| Restic | Backs up `dock-prod`'s own filesystem (`/home/hughboi`) — has to run on the host it's backing up, by definition. A separate k3s-native backup job (for Longhorn PVCs) would be a new, different thing, not a migration of this one. |
| UniFi | Core network management (APs/switches). The k3s manifest could technically give it a stable IP via MetalLB, but this isn't the place to pilot the k3s migration pattern. |
| Traefik, Bind9, CrowdSec, Gitea, Semaphore, promgraftail | Fixed network position or hard dependency for everything else (reverse proxy, canonical DNS, ingress security, static-IP-pinned routing, the log-shipping destination every other service points at). Each needs its own dedicated re-plumbing project before it can move. |

**Ready to migrate, real data move required first:**

| Service | Status |
|---|---|
| Paperless-ngx | The k3s manifest now points `data`/`media` at NFS/TrueNAS exports (not Longhorn) — same low-risk pattern as Jellyfin/Immich's external library. Docker's copy still lives on `dock-prod` local volumes, though, so migrating means `rsync`-ing that data to the new TrueNAS export first, then redeploying. See `apps/kubernetes/k3s/apps/paperless-ngx/README.md` for the exact steps. |

**Good k3s candidates not deployed yet** (20 services — small/self-contained state, no storage or network-position tie):

1. change-detection
2. ezbookkeeping
3. fasten-health
4. freshrss
5. hoarder
6. mealie
7. n8n
8. ntfy
9. pocket-id
10. searxng
11. syncthing
12. vaultwarden
13. mailrise
14. gatus
15. home-assistant
16. homepage
17. tube-archivist
18. file-browser
19. docs — the static Hugo site
20. Wazuh — never deployed on Docker at all; build fresh directly on k3s once it's live, since it's fleet-wide security monitoring that specifically shouldn't share a host with the things it watches

---

## Bootstrap Order

A full rebuild from bare metal follows this order:

```text
 1. Network      → VLANs, firewall rules, PXE DHCP options in UniFi
 2. PXE          → Register nodes in local.ipxe + TOML, boot via Libre Potato
 3. Athena        → SOPS + age setup, Gitea, Semaphore, Bind9
 4. TrueNAS      → ZFS pools, NFS datasets, MTU 9000 on VLAN 40
 5. Proxmox      → Disable enterprise repo, form cluster, API tokens, QDevice
 6. VM Template  → Build Template 9999 via Ansible playbook (or Packer for custom packages)
 7. Terraform    → Provision all VMs: Athena, dock-prod, 9× k3s nodes
 8. Ansible      → ssh-keyscan, new-host-bootstrap, k3s install, Docker on dock-prod
 9. Docker services → dock-prod, DNS-dependent services first
10. k3s (once reconfigured) → kube-vip → MetalLB → Longhorn → Sealed Secrets →
                                cert-manager → Traefik → CrowdSec → ArgoCD
11. Semaphore    → Wire up scheduled maintenance jobs
```

This is a high-level summary, not a 1:1 map to `docs/QUICKSTART.md`'s numbered phases (Phase 0–8)
— QUICKSTART.md is the source of truth for exact current ordering and command-level detail.

---

## Security Layers

| Layer | Tool | Status |
|-------|------|--------|
| Edge | CrowdSec | Active — hard dependency for all Traefik traffic (see `apps/docker/crowdsec/README.md`) |
| Ingress | Traefik | Active — TLS termination, routing, auth middleware |
| Certs | Let's Encrypt via Cloudflare DNS-01 | Active |
| SIEM | Wazuh | Not yet deployed anywhere — build directly on k3s, next up (see k3s Migration Plan above) |
| Secrets (Docker/provisioning) | SOPS + Age | Active — ~20/36 Docker services migrated as of this writing |
| Secrets (k3s) | Sealed Secrets | Controller manifest exists, **not adopted by any app yet** — see `docs/8-gitops/index.md` |
| Identity | Pocket ID | Active on Docker (OIDC/SSO) — preferred over Authentik's more complex setup. Authentik itself was tried and sunset (`apps/docker/sunset/authentik/`); a k3s manifest exists as unrealized planning only |

---

## DNS Strategy

**One domain, `hughboi.cc`, for everything — no domain-per-platform split.** DNS resolves per
hostname, not per domain: each service's own record (`jellyfin.hughboi.cc`,
`vaultwarden.hughboi.cc`, etc.) points at whichever Traefik instance currently serves that
service — dock-prod's Traefik (`10.10.10.10`) today, or k3s's Traefik/MetalLB IP
(`10.10.30.75`) once a service has actually migrated. Migrating a service later is a single DNS
record change, not a domain change.

Internal LAN DNS resolution is Bind9 on Athena, not AdGuard — AdGuard's Docker instance handles
ad-blocking for browsing/guest traffic. See `apps/docker/adguard/README.md` for the real current
split.

---

## CI/CD

**CI** (`.gitea/workflows/ci.yaml`) runs on every push/PR: YAML lint, kubeconform, Terraform
validate, Ansible lint, secret scanning, and SOPS coverage checking.

**Renovate** (`renovate.json`) opens PRs for Docker Compose / Terraform / Ansible dependency
updates on a weekly schedule, with per-service automerge rules (patch versions auto-merge;
databases, Gitea, Authentik, and k3s itself never automerge). Merging a Renovate PR does not yet
auto-trigger a deploy — that's tracked as [Gitea issue #45](https://gitea.hughboi.cc/hughboi/homelab/issues/45).

Docker Compose deploys go through Semaphore's `sops-deploy` Task Template
(`ansible/playbooks/docker/sops-deploy/`), triggered manually per-service today.

---

## Storage

| Tier | Backend | Used for |
|------|---------|---------|
| NFS | TrueNAS | Media, large datasets — Jellyfin, Immich, Paperless-ngx, Tube Archivist, RomM |
| Local disk | `dock-prod` | Named Docker volumes for app state (databases, caches, small config) |
| Block | Longhorn | k3s app PVCs — in use by services that have migrated |

---

## Key Files

| File | Purpose |
|------|---------|
| `docs/QUICKSTART.md` | Current phase-by-phase bootstrap walkthrough |
| `apps/kubernetes/k3s/README.md` | Full cluster bootstrap + operational runbooks (target state) |
| `apps/docker/*/README.md` | Per-service setup, secrets, and real deployment notes for what's actually running |
| `scripts/sops-check.sh` | Current SOPS migration status across all Docker services |
| `terraform/proxmox/README.md` | VM provisioning + state backend |
| `ansible/README.md` | Inventory + vault setup |
| `renovate.json` | Dependency update config |
| `.gitea/workflows/ci.yaml` | CI pipeline |
