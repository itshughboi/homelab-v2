---
title: "Homelab"
---

# hughboi homelab

> Infrastructure as code. Everything in Git. Rebuild from bare metal in under 20 minutes.

---

## Start Here

- **Rebuilding from scratch?** → [Master Guide (Runbook)](master-guide) — phases 1–13, commands only
- **Need context or troubleshooting?** → Open the section in the sidebar

---

## Stack at a Glance

```
4× Proxmox nodes  →  PXE boot  →  Terraform VMs  →  Ansible bootstrap
                                                               │
                                          ┌────────────────────┤
                                          ▼                    ▼
                                  Athena (mgmt)         dock-prod
                                  Gitea · Semaphore      Vaultwarden
                                  Traefik · Bind9        Jellyfin · n8n
                                          │
                                          ▼
                                  k3s cluster (9 nodes)
                                  ArgoCD · Longhorn
                                  Traefik · cert-manager
```

---

## Quick Reference

| Host | IP | Role |
| --- | --- | --- |
| pve-srv-1–4 | 10.10.10.1–4 | Proxmox cluster |
| Athena | 10.10.10.8 | Management VM |
| dock-prod | 10.10.10.10 | Production Docker |
| Libre Potato | 10.10.99.99 | PXE netboot |
| k3s-api-vip | 10.10.30.30 | k3s control plane |
| traefik-vip | 10.10.30.65 | k3s ingress |

| VLAN | ID | Subnet | Purpose |
| --- | --- | --- | --- |
| Management | 10 | 10.10.10.0/24 | SSH, Web UIs, DNS |
| Cluster | 20 | 10.10.20.0/24 | Corosync only — no gateway |
| k3s | 30 | 10.10.30.0/24 | Workloads |
| Storage | 40 | 10.10.40.0/24 | TrueNAS, PBS — MTU 9000 |
| Torrent | 49 | 172.16.20.0/24 | Airgapped |
| VPN | 80 | 10.10.80.0/24 | Tailscale |
| Provisioning | 99 | 10.10.99.0/24 | PXE boot |
