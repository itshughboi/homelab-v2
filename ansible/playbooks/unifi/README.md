# UniFi Ansible Playbook — REFERENCE (not in use)

> [!WARNING] Not in use — UniFi is managed manually
> Like [`terraform/unifi/`](../../../terraform/unifi/README.md), this playbook is kept as a
> **reference implementation** only. The live network is configured **by hand in the UI** and
> documented in [docs/1-networking/](../../../docs/1-networking/). Its `group_vars/all.yaml`
> still encodes pre-decision values (e.g. a VLAN 30 DHCP pool — DHCP is now **disabled** on
> VLANs 20/30/40) — the docs, not this playbook, are the source of truth.

Provisions all UniFi networks via `community.general.unifi_network`. Run from Semaphore on Athena after UniFi is up.

## Prerequisites

- Local UniFi admin account (cloud accounts don't work with the API)
- Credentials: copy `group_vars/unifi.yaml.example` → `group_vars/unifi.yaml` (gitignored) and
  fill in. If you ever commit it, encrypt first:

```sh
ansible-vault encrypt group_vars/unifi.yaml
```

Run with:
```sh
ansible-playbook site.yaml --ask-vault-pass
```

## What This Manages

All networks defined in `group_vars/all.yaml`:

| Network | VLAN | Notes |
| --- | --- | --- |
| Management | 10 | DHCP 100–200 |
| Cluster | 20 | DHCP disabled — Corosync only |
| k3s | 30 | DHCP pool .200–.220 (lower range reserved for static IPs) |
| Storage | 40 | DHCP disabled — MTU 9000 on switch ports, configure manually |
| IoT | 50 | DHCP 10–200 |
| Tailscale VPN | 80 | DHCP 1–20 |
| Torrent | 49 | DHCP 1–20, airgapped |
| Provisioning | 99 | PXE: TFTP 10.10.99.99, file ipxe.efi |

## What This Does NOT Manage

- **WireGuard VPN (VLAN 81)** — UniFi VPN Server UI only; `community.general.unifi_network` can't configure VPN servers
- **Proxmox virtual interfaces** — handled by `ansible/playbooks/ubuntu/proxmox/virtual-interfaces`
- **Switch port MTU / profiles** — configure jumbo frames and trunk profiles manually in UniFi
- **Firewall rules** — see `docs/1-networking/Unifi/Firewall.md`
