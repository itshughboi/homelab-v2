# Homelab

Self-hosted infrastructure running on Proxmox, managed with IaC (Terraform + Packer + Ansible) and GitOps (ArgoCD). All user services run behind Traefik with Let's Encrypt TLS.

> **Migration in progress:** Docker Compose stack (`*.hughboi.cc`) is being replaced by k3s (`*.hughboi.vip`). Everything in `apps/kubernetes/` is the target state.

---

## Principles

**Everything is code.** Network config, VM provisioning, k8s manifests, DNS records — all live in Git. Rebuilding from bare metal is a known, repeatable process.

**Separation of planes.** Management never mixes with storage or workload traffic. VLANs enforce this at the switch, not just the firewall.

**GitOps over manual.** Push to Git → automation applies it. No SSH-and-edit habits that create undocumented state.

**Secrets never touch Git unencrypted.** SOPS + Age is the rule. Once a plaintext secret hits Git history, rotation is mandatory regardless of deletion.

**Blast radius by design.** A compromised workload container cannot pivot to management or storage — the VLAN firewall rules make it structurally impossible.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Proxmox Cluster (4 nodes: pve-srv-1/2/3/4)         │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │  k3s Cluster                                 │   │
│  │  Masters:  10.10.30.1-3  (VIP: 10.10.30.30) │   │
│  │  Workers:  10.10.30.11-13                    │   │
│  │  Longhorn: 10.10.30.51-53                    │   │
│  │                                              │   │
│  │  MetalLB pool: 10.10.30.60-99               │   │
│  │  Traefik:  10.10.30.75  (*.hughboi.vip)     │   │
│  │  AdGuard:  10.10.30.65                      │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  Docker host (dock-prod) — legacy, being migrated   │
└─────────────────────────────────────────────────────┘
          │
          ▼
  TrueNAS (NFS: media, backups)
```

---

## Repository Layout

```
homelab/
├── apps/
│   ├── kubernetes/k3s/     # k3s cluster — source of truth for GitOps
│   │   ├── infra/          # kube-vip, MetalLB, Longhorn, system-upgrade-controller
│   │   ├── networking/     # Traefik, cert-manager, CrowdSec, Reflector, AdGuard
│   │   ├── monitoring/     # kube-prometheus-stack, Loki, Alloy, Alertmanager
│   │   ├── argocd/         # ArgoCD install + App of Apps
│   │   └── apps/           # ~30 user-facing services
│   └── docker/             # Legacy Docker Compose (read-only reference)
├── ansible/                # OS provisioning, k3s install, Docker host setup
├── terraform/proxmox/      # VM provisioning (bpg/proxmox provider)
├── packer/                 # Ubuntu cloud-init template for Proxmox
├── bootstrap/              # PXE / netboot.xyz setup
└── docs/                   # Architecture notes, decisions
```

---

## To Do

Manual steps not yet applied to the live cluster:

- [ ] **Apply k3s Prometheus IngressRoute** — exposes `prometheus.hughboi.vip` so dock-prod Grafana can use k3s as a data source
  ```sh
  kubectl apply -f apps/kubernetes/k3s/monitoring/kube-prometheus-stack/prometheus-ingressroute.yaml
  ```
- [ ] **Add k3s Prometheus as data source in dock-prod Grafana** — URL: `https://prometheus.hughboi.vip`
- [ ] **Add node_exporter to dock-prod** so k3s Prometheus can scrape Docker host metrics (see `apps/kubernetes/k3s/monitoring/README.md`)
- [ ] **Run bind_exporter playbook on Athena** — enables Bind9 metrics in Prometheus
  ```sh
  cd ansible/playbooks/ubuntu/bind-exporter
  ansible-playbook main.yaml -i <athena-inventory>
  ```
  Then import Grafana dashboard **1666** for Bind9 visualisation.

---

## Bootstrap Order

A full rebuild from bare metal follows this order:

```
 1. Network      → VLANs, firewall rules, PXE DHCP options in UniFi
 2. PXE          → Register nodes in local.ipxe + TOML, boot via Libre Potato
 3. TrueNAS      → ZFS pools, NFS datasets, MTU 9000 on VLAN 40
 4. Proxmox      → Disable enterprise repo, form cluster, API tokens, QDevice
 5. VM Template  → Build Template 9999 via Ansible playbook (or Packer for custom packages)
 6. Terraform    → Provision all VMs: Athena, dock-prod, 9× k3s nodes
 7. Ansible      → ssh-keyscan, new-host-bootstrap, k3s install, Docker on dock-prod
 8. Athena       → SOPS + age setup, start Docker services (DNS first), push repo to Gitea
 9. k3s infra    → kube-vip → MetalLB → Longhorn → Sealed Secrets
10. k3s network  → cert-manager → Traefik → CrowdSec → Reflector → AdGuard
11. k3s observ.  → kube-prometheus-stack → Loki → Alloy
12. GitOps       → ArgoCD install → register Gitea repo → apply root-app.yaml
13. Semaphore    → Wire up scheduled maintenance jobs
```

Detailed commands for each phase live in the numbered `docs/` folders:
- Steps 1–2: `docs/1-networking/` and `docs/2-prep/`
- Steps 3: `docs/5-storage/`
- Steps 4–6: `docs/3-proxmox/provisioning/`
- Steps 7–8: `docs/8-k3s/` and `docs/4-athena/`
- Steps 9–13: `docs/8-k3s/`

---

## Security Layers

| Layer | Tool | Responsibility |
|-------|------|----------------|
| Edge | CrowdSec | Blocks known-bad IPs before they hit Traefik |
| Ingress | Traefik | TLS termination, routing, auth middleware |
| Certs | cert-manager | Let's Encrypt wildcard via Cloudflare DNS-01 |
| SIEM | Wazuh | Log analysis, file integrity, anomaly alerts |
| Host OS | UFW | SSH + port protection on Docker host |
| Secrets | Sealed Secrets | Encrypted secrets safe to commit to Git |
| Identity | Authentik | OIDC/SSO for all k8s services |

---

## DNS Strategy

| Domain | Purpose | Resolver |
|--------|---------|---------|
| `*.hughboi.vip` | k8s services | AdGuard → Traefik (10.10.30.75) |
| `*.hughboi.cc` | Docker services (legacy) | AdGuard → Traefik (Docker) |
| `*.hughboi.vip` wildcard TLS | cert-manager + Cloudflare DNS-01 | N/A |

---

## GitOps Flow

```
This repo (Gitea: gitea.hughboi.vip)
    │
    ├── push to main
    │
    ▼
ArgoCD polls Gitea every 3 minutes
    │
    ├── App of Apps pattern (apps-appset.yaml)
    │   └── auto-discovers apps/kubernetes/k3s/apps/* directories
    │
    ▼
ArgoCD syncs changed manifests to the cluster
    │
    ├── prune: true  (removes resources deleted from repo)
    └── selfHeal: true  (reverts manual kubectl changes)
```

**Renovate** (in-cluster CronJob) opens PRs weekly for image/chart updates.  
**CI** (`.gitea/workflows/ci.yaml`) runs YAML lint, kubeconform, Terraform validate, Ansible lint, secret scanning, and SOPS coverage on every push and PR.

---

## Storage

| Tier | Backend | Used for |
|------|---------|---------|
| Block (default) | Longhorn | App PVCs (databases, state) |
| NFS | TrueNAS | Media, large datasets (Immich, Jellyfin, ROMM) |
| ConfigMap | etcd | Stateless config, dashboards |

Longhorn: 3-node replication, hourly snapshots, daily backups to NFS/S3. See `infra/longhorn/recurringjob.yaml`.

---

## Monitoring

| Tool | URL | Purpose |
|------|-----|---------|
| Grafana | grafana.hughboi.vip | Dashboards (k8s, nodes, Proxmox, apps) |
| Prometheus | (internal) | Metrics storage (30d retention) |
| Loki | (internal) | Log aggregation |
| Alertmanager | (internal) | Routes alerts → Discord + email (mailrise) |
| Gatus | gatus.hughboi.vip | Uptime / service health status page |

---

## Active Services (k8s)

| Service | URL | Notes |
|---------|-----|-------|
| ArgoCD | argocd.hughboi.vip | GitOps |
| Gitea | gitea.hughboi.vip | Git + CI runner |
| Authentik | auth.hughboi.vip | SSO (OIDC) |
| Vaultwarden | vault.hughboi.vip | Password manager |
| Immich | photos.hughboi.vip | Photo management |
| Paperless-NGX | paperless.hughboi.vip | Document management |
| Home Assistant | ha.hughboi.vip | Home automation |
| Grafana | grafana.hughboi.vip | Monitoring dashboards |
| Semaphore | semaphore.hughboi.vip | Ansible UI |
| Ntfy | ntfy.hughboi.vip | Push notifications |

Full app list: `apps/kubernetes/k3s/apps/`

---

## Still on Docker (intentional)

| Service | Reason |
|---------|--------|
| Pocket ID | Preferred for Docker SSO (simpler UI than Authentik) |
| Wazuh | Complex multi-container SIEM — migration path in `apps/docker/wazuh/README.md` |
| Gitea runner | Needs Docker socket — stays on Docker host |
| Restic | Backs up Docker host filesystem — superseded once migration completes |

---

## Key Files

| File | Purpose |
|------|---------|
| `apps/kubernetes/k3s/README.md` | Full cluster bootstrap + operational runbooks |
| `apps/kubernetes/k3s/argocd/apps/apps-appset.yaml` | App of Apps ApplicationSet |
| `apps/kubernetes/k3s/networking/traefik/README.md` | TLS + ingress setup |
| `apps/kubernetes/k3s/infra/sealed-secrets/README.md` | Secret encryption workflow |
| `apps/kubernetes/k3s/infra/velero/README.md` | Cluster backup + DR |
| `terraform/proxmox/README.md` | VM provisioning + state backend |
| `ansible/README.md` | Inventory + vault setup |
| `renovate.json` | Dependency update config |
| `.gitea/workflows/ci.yaml` | CI pipeline |
