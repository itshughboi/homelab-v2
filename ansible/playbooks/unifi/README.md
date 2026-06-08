# UniFi Ansible Playbook

Provisions all UniFi networks via `community.general.unifi_network`. Run from Semaphore on Athena after UniFi is up.

## Prerequisites

- Local UniFi admin account (cloud accounts don't work with the API)
- Credentials in `group_vars/unifi.yaml`, encrypted with Ansible Vault:

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
