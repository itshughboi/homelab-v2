# 1. Networking

All networking is built on UniFi (UXG Max + USW Flex Mini). Configure manually through the UI — see [Unifi/Overview.md](Unifi/Overview.md) for initial setup order.

---

## UniFi

| File | Contents |
| --- | --- |
| [Overview.md](Unifi/Overview.md) | Controller access, bootstrap order of operations |
| [Networks/](Unifi/Networks/README.md) | VLAN table, DNS, WiFi, VPN, PXE, LACP, mDNS, QoS |
| [Firewall/](Unifi/Firewall/README.md) | Zone-based firewall rules, setup, reference, recovery |
| [Security/](Unifi/Security/README.md) | IPS, region blocking, honeypot, logging, hardening |
| [Assignments/](Unifi/Assignments/MAC%20Reservations.md) | MAC reservations, switch ports, network assignments |
| [Ansible.md](Unifi/Ansible.md) | Ansible integration reference (not active — see file for why) |

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
