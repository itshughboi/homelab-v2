# 1. Networking

All networking is built on UniFi (UXG Max + USW Flex Mini). Configure manually through the UI — see [Unifi/Overview.md](Unifi/Overview.md) for initial setup order.

---

## Before You Start

### Credentials (gather before touching hardware)

| Credential | Where to get it | Used by |
| --- | --- | --- |
| Cloudflare API Token | Cloudflare → My Profile → API Tokens → Zone:DNS:Edit | cert-manager, Traefik TLS |
| Cloudflare Zone ID | Cloudflare → domain overview | cert-manager |
| Discord webhook URL | Channel → Edit → Integrations → Webhooks | Alertmanager, Semaphore, n8n |
| SSH public key | `cat ~/.ssh/id_ed25519.pub` | Packer, Terraform, Ansible |
| IGDB Client ID + Secret | dev.twitch.tv → create app | RomM |
| SteamGridDB API key | steamgriddb.com → preferences → API | RomM |
| RetroAchievements API key | retroachievements.org → settings | RomM |

### Tooling (laptop)

```sh
brew install terraform ansible packer git age sops helm
brew install --cask docker
```

### SSH Key — Dedicated Homelab Keypair

Create a separate keypair for the homelab. This gets injected into every node at build time — don't reuse your personal key.

```sh
ssh-keygen -t ed25519 -C "homelab-datacenter" -f ~/.ssh/homelab_id_ed25519
```

Store the private key locally for now, in Vaultwarden once it's running.

### Clone the Repo

```sh
git clone https://gitea.hughboi.cc/hughboi/homelab.git
cd homelab
```

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
