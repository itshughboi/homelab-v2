# 1. Networking

All networking is built on UniFi (UXG Max + USW Flex Mini). Configure manually through the UI — see [Unifi/Overview.md](Unifi/Overview.md) for initial setup order.

---

## UniFi

| File | Contents |
| --- | --- |
| [Overview.md](Unifi/Overview.md) | Controller access, bootstrap order of operations |
| [Networks.md](Unifi/Networks.md) | VLAN table, DNS config, mDNS, IGMP, Jumbo Frames, QoS |
| [VLANs + VMs.md](Unifi/VLANs%20+%20VMs.md) | DHCP ranges, mDNS forwarding, per-VLAN notes |
| [VPN.md](Unifi/VPN.md) | Tailscale (VLAN 80) + WireGuard (VLAN 81) |
| [Firewall/](Unifi/Firewall/README.md) | Zone-based firewall rules, setup, reference, recovery |
| [PXE Options.md](Unifi/PXE%20Options.md) | DHCP boot options 66/67, switch port assignments |
| [MAC Reservations.md](Unifi/MAC%20Reservations.md) | Static IP assignments for core infrastructure |
| [Static Clients.md](Unifi/Static%20Clients.md) | Network assignment list |
| [Switch_Port_Assignments.md](Unifi/Switch_Port_Assignments.md) | Physical port layout |
| [WiFi.md](Unifi/WiFi.md) | Channel AI, WiFiman, guest speed limit |
| [Security.md](Unifi/Security.md) | IPS, region blocking, honeypot, NetFlow |
| [Ansible.md](Unifi/Ansible.md) | Ansible integration reference (not active — see file for why) |
| [LACP - MLAG.md](Unifi/LACP%20-%20MLAG.md) | Bonding notes for future switch upgrade |

---

## Proxmox

| File | Contents |
| --- | --- |
| [Proxmox/Virtual Interfaces.md](Proxmox/Virtual%20Interfaces.md) | VLAN bridge config for all nodes (pve-srv-1 through 4) |

---

## Alternative Methods

| File | Contents |
| --- | --- |
| [Using Console Cable.md](Alternative%20Methods/Using%20Console%20Cable.md) | Serial access when SSH is unavailable |
| [Unifi EdgeRouter 4.md](Alternative%20Methods/Unifi%20EdgeRouter%204.md) | Archived — CLI reference for DHCP/PXE on EdgeRouter |
| [Terraform.md](Alternative%20Methods/Terraform.md) | Archived — why Terraform was dropped for UniFi |
| [OPNsense.md](Alternative%20Methods/OPNsense.md) | Archived — OPNsense notes |
