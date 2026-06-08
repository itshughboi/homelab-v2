## Accessing the Controller

The UniFi Network Application runs as a Docker container on dock-prod (`10.10.10.10`).
A Ubiquiti cloud account is linked to it — unifi.ui.com provides remote access to this same self-hosted controller.

| Access | URL | When to use |
| --- | --- | --- |
| Local | `https://10.10.10.10:8443` | Normal day-to-day — faster, no cloud dependency |
| Remote | `https://unifi.ui.com` | Out-of-band access, or making risky firewall changes (cloud survives a self-inflicted lockout as long as WAN stays up) |

**SSH into UXG Max:**
```sh
ssh ubnt@<uxg-max-ip>
configure
```

**Factory reset / new device defaults:** `ubnt / ubnt`

---

## Order of Operations

Build network → Secure it → Add services

1. Power on UXG Max, plug laptop into LAN port 1, go to `192.168.1.1`
2. Configure in this order:
   1. WAN — DHCP
   2. WAN DNS — `9.9.9.9`, `1.1.1.1` or `1.1.1.2`
   3. VLANs — see [Networks/](Networks/README.md)
   4. DHCP PXE options 66/67 on VLAN 99 — see [Networks/PXE Options.md](Networks/PXE%20Options.md)
   5. Firewall — see [Firewall/](Firewall/README.md)
   6. LACP / MLAG if applicable — see [Networks/LACP - MLAG.md](Networks/LACP%20-%20MLAG.md)
   7. MAC reservations (static IPs for core infra):
      - Libre Potato → `10.10.99.99`
      - Proxmox servers → see [Assignments/MAC Reservations.md](Assignments/MAC%20Reservations.md)
   8. Netboot provisioning — see [Networks/Netboot.md](Networks/Netboot.md)

> [!NOTE]
> All UniFi configuration is done manually through the UI. Set it once, take a backup, and leave it.
> The UniFi UI changes faster than the Ansible collection keeps up — see [Ansible.md](Ansible.md) for why that approach was shelved.
> Enable **auto-backup** in UniFi settings and take a manual backup before any significant change.

---

## Backups

Settings → System → Backup

**Schedule:** Monday / Wednesday / Friday, keep 12 backups (~1 month of coverage)

**Cloud sync:** Not available for self-hosted controllers — automated backups are local only. Offsite backup requires syncing the backup directory out of the Docker container manually (e.g. cron job copying to TrueNAS or File Browser).

**Before any significant change** (firewall rules, VLAN restructure, firmware update): take a manual backup first. Settings → System → Backup → Download Backup.
