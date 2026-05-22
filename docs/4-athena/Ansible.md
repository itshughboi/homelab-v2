# Ansible

---

## Prerequisites

1. **Local admin account in UniFi** — create one specifically for Ansible.
   Cloud accounts will not work.

2. **Install the UniFi collection** on the Ansible machine:
```sh
ansible-galaxy collection install community.general
```

3. Management network must have DHCP option pointing to the netbootxyz machine to load iPXE.
   See `iac/bootstrap/README.md` for details.

---

## What Ansible Configures

### Networks (can all be done via Ansible after initial manual bootstrap)

| Name | VLAN | CIDR | Notes |
| --- | --- | --- | --- |
| Management | 10 | 10.10.10.0/24 | SSH, Web UI, Unifi, Bind9 |
| Cluster | 20 | 10.10.20.0/24 | Corosync |
| k3s | 30 | 10.10.30.0/24 | |
| Storage | 40 | 10.10.40.0/24 | TrueNAS, PBS, Longhorn |
| VPN | 80 | 10.10.80.0/24 | Tailscale |
| Torrent | 49 | 172.16.20.0/24 | Airgapped from internal |
| Provisioning | 99 | 10.10.99.0/24 | Netboot |

### Proxmox Nodes (each node needs)

- 3 virtual interfaces (vmbr1.10, vmbr1.20, vmbr1.40)
- pve-srv-1 needs 2+ physical NICs
- QoS applied to VLAN 20 to prioritize Corosync traffic
- Jumbo Frames enabled on VLAN 40 (MTU 9000)

### Athena (management VM)
- Docker
- Traefik
- Gitea
- Semaphore (Ansible UI / scheduler)
- Bind9

---

## Ansible Flow

1. Configure UniFi manually — create Management (VLAN 10) and Provisioning (VLAN 99)
   with netboot options. This is the bootstrap minimum.
2. Provision Athena (via Terraform cloning the Cloud-Init template).
3. Run Ansible from laptop against Athena to install the management stack.
4. From this point, Athena runs Ansible via Semaphore. Laptop is retired.
5. Ansible handles all remaining network creation, IP assignments, service config.
   Changes in either the UI or Ansible are fine — Ansible skips anything already correct.

---

## Key Notes

**VLAN 20 (Corosync):** Very sensitive to latency. Flooding a NIC with backups or storage
traffic can cause jitter and trigger a Fencing event (hard reboot). Ansible applies QoS
tagging (UDP 5404–5405, DSCP 46) automatically. No gateway — internal routing only.

**VLAN 40 (Storage):** PBS or Longhorn can saturate the management NIC. Ansible enables
Jumbo Frames (MTU 9000). No gateway — internal routing only.

> [!DANGER] Jumbo Frames
> Every device on VLAN 40 (Proxmox, TrueNAS, PBS) MUST support and be configured for
> MTU 9000, or packets will drop. Jumbo packets cannot traverse the internet — this VLAN
> is internal-only by design.
