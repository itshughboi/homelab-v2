# Homelab

Self-hosted infrastructure running on Proxmox, managed with IaC (Terraform + Packer + Ansible). All user services run behind Traefik with Let's Encrypt TLS.

> [!IMPORTANT] Current state (2026-07)
> **Almost everything runs on Docker (`dock-prod`) today.** k3s is the target architecture for
> most workloads, but the cluster is **not currently live** — it needs reconfiguring before any
> real migration can start. `apps/kubernetes/k3s/` holds real manifest work already done ahead
> of that (29 services have manifests written), but having a manifest doesn't mean a service is
> running there. Don't trust a service's presence in `apps/kubernetes/k3s/apps/` as evidence it's
> live — check `apps/docker/` and the service's own README for what's actually deployed.

---

## Principles

**Everything is code.** Network config, VM provisioning, k3s manifests, DNS records — all live in Git. Rebuilding from bare metal is a known, repeatable process.

**Separation of planes.** Management never mixes with storage or workload traffic. VLANs enforce this at the switch, not just the firewall.

**GitOps over manual.** Push to Git → automation applies it, where automation exists yet (Semaphore for Ansible/Docker deploys today; ArgoCD is planned for k3s once it's live).

**Secrets never touch Git unencrypted.** SOPS + Age is the rule for Docker/provisioning secrets — active today, ~20/36 Docker services migrated as of this writing (`./scripts/sops-check.sh` for current count). Sealed Secrets is the planned equivalent for k3s once it's live; the controller manifest exists but nothing uses it yet.

**Blast radius by design.** A compromised workload container cannot pivot to management or storage — the VLAN firewall rules make it structurally impossible.

---

## Architecture (today)

```text
┌──────────────────────────────────────────────────────────┐
│  Proxmox Cluster (pve-srv-1/2/3/4)                        │
│                                                            │
│  pve-srv-1 → dock-prod (10.10.10.10)                      │
│    Docker host — almost everything user-facing runs here  │
│    Traefik (*.hughboi.cc), AdGuard, Vaultwarden, Jellyfin, │
│    Immich, Paperless-ngx, Home Assistant, ~30 more         │
│                                                            │
│  pve-srv-1 → Athena (10.10.10.8)                           │
│    Management: Gitea, Semaphore, Bind9 (canonical DNS)     │
│                                                            │
│  pve-srv-2/3/4 → k3s cluster (NOT currently live)          │
│    Masters: 10.10.30.1-3 (VIP 10.10.30.30)                 │
│    Workers: 10.10.30.11-13, Longhorn: 10.10.30.51-53       │
│    Same domain (hughboi.cc) — per-service DNS record       │
│    points at whichever Traefik currently serves it         │
└──────────────────────────────────────────────────────────┘
          │
          ▼
  TrueNAS (NFS: media, backups, documents)
```

---

## Repository Layout

```text
homelab/
├── apps/
│   ├── docker/              # What's actually running today — ~36 services on dock-prod
│   └── kubernetes/k3s/      # k3s manifests — target state, cluster not yet live
│       ├── infra/           # kube-vip, MetalLB, Longhorn, system-upgrade-controller
│       ├── networking/      # Traefik, cert-manager, CrowdSec, AdGuard
│       ├── monitoring/      # kube-prometheus-stack, Loki, Alloy, Alertmanager
│       ├── argocd/          # ArgoCD install + App of Apps (not yet running)
│       └── apps/            # 29 services with manifests prepared, most not yet deployed
├── ansible/                 # OS provisioning, k3s install, Docker host setup
├── terraform/proxmox/       # VM provisioning (bpg/proxmox provider)
├── packer/                  # Ubuntu cloud-init template for Proxmox
├── bootstrap/                # PXE / netboot.xyz setup (provisioning-time only)
└── docs/                    # Architecture notes, numbered setup guides
```

---

## k3s Migration Plan

A full audit of every Docker service's real storage/network dependencies determined what's
actually a good k3s candidate versus what has a real reason to stay on `dock-prod`. Full
per-service reasoning: see the categorized reference published as an Artifact during the
planning session — ask in a future session if the link needs regenerating, or reconstruct from
`apps/kubernetes/k3s/apps/` (a manifest existing there means it was considered a candidate; it
does not mean it's deployed).

**Staying on Docker/`dock-prod`, with real reasons:**

| Service | Why it stays |
|---|---|
| Jellyfin | GPU transcoding — Intel Arc A380 is passed through on `dock-prod`. k3s nodes only have AMD Radeon iGPUs, benchmarked as a real downgrade for concurrent 4K/HDR transcoding. Revisit once `dock-prod`'s hardware is upgraded and the Arc A380 is retired. |
| Immich | Real photo libraries are large and TrueNAS-hosted; the k3s manifest uses a 100Gi Longhorn PVC for the library itself (not NFS passthrough), so moving means migrating real data into Longhorn — a deliberate future project, not a simple redeploy. |
| Paperless-ngx | Same reasoning as Immich — document library lives on Longhorn in the k3s manifest, not NFS passthrough. |
| Restic | Backs up `dock-prod`'s own filesystem (`/home/hughboi`) — has to run on the host it's backing up, by definition. A separate k3s-native backup job (for Longhorn PVCs) would be a new, different thing, not a migration of this one. |
| UniFi | Core network management (APs/switches). The k3s manifest could technically give it a stable IP via MetalLB, but this isn't the place to pilot the k3s migration pattern. |
| Traefik, Bind9, CrowdSec, Gitea, Semaphore, promgraftail | Fixed network position or hard dependency for everything else (reverse proxy, canonical DNS, ingress security, static-IP-pinned routing, the log-shipping destination every other service points at). Each needs its own dedicated re-plumbing project before it can move. |

**Good k3s candidates once the cluster is live** (20 services — small/self-contained state, no storage or network-position tie):

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
| SIEM | Wazuh | Not yet deployed anywhere — planned for k3s once live (see k3s Migration Plan above) |
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

`apps/kubernetes/k3s/` currently has some manifests referencing a separate `*.hughboi.vip`
domain from earlier planning — that convention is **not** the intended long-term design and
should be updated to `hughboi.cc` as those manifests are actually put into use, not treated as
the real target.

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
| Block (planned) | Longhorn | k3s app PVCs — not in use yet, k3s isn't live |

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
