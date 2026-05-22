# Homelab

Self-hosted infrastructure running on Proxmox, managed with IaC (Terraform + Packer + Ansible) and GitOps (ArgoCD). All user services run behind Traefik with Let's Encrypt TLS.

> **Migration in progress:** Docker Compose stack (`*.hughboi.cc`) is being replaced by k3s (`*.hughboi.vip`). Everything in `apps/kubernetes/` is the target state.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Proxmox Cluster (3 nodes: pve-srv-1/2/3)           │
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

A full rebuild from scratch follows this order:

```
1. Packer       → build Ubuntu VM template in Proxmox (packer/proxmox-iso-ubuntu/)
2. Terraform    → provision k3s master/worker/longhorn VMs (terraform/proxmox/)
3. Ansible      → configure OS, install k3s (ansible/playbooks/kubernetes/k3s/)
4. kubectl      → deploy infra layer (kube-vip → MetalLB → Longhorn)
5. kubectl      → deploy networking (cert-manager → Traefik → CrowdSec → Reflector → AdGuard)
6. kubectl      → deploy monitoring (kube-prometheus-stack → Loki → Alloy)
7. Helm         → install sealed-secrets (before ArgoCD — bootstrapping constraint)
8. Helm         → install ArgoCD
9. kubectl      → apply root-app → ArgoCD syncs all remaining apps automatically
```

See `apps/kubernetes/k3s/README.md` for detailed commands.

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
**CI** (`.gitea/workflows/lint.yml`) runs YAML lint, kubeconform, Helm lint, and `terraform fmt` on every push.

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
| `.gitea/workflows/lint.yml` | CI pipeline |
