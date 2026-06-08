# [ARCHIVED] Ventoy Fallback (Manual USB Install)

> **Status: Break-glass only.** All nodes — including pve-srv-1 — provision via netboot.
> The Libre Potato on VLAN 99 is independent of any Proxmox node, so there is no
> "first node" exception. Only reach for this if the Libre Potato itself is dead or
> netboot is otherwise unavailable.

Use this when netboot is unavailable or you need a one-off install without the full PXE chain.

---

## Prepare Ventoy

1. Rename the main Ventoy partition (where ISOs live) to `PROXMOX_AIC`

> [!DANGER]
> The partition must be named exactly `PROXMOX_AIC` or the automated answer file
> will be ignored and you'll get a manual install prompt.

2. Download the Proxmox VE ISO from https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso
   and copy it to the Ventoy partition

---

## Answer File

3. Create `answer.toml` adjacent to the ISO on the Ventoy partition:

```toml
[global]
keyboard = "us"
timezone = "America/Denver"
# Generate hashed password: printf "yourpassword" | openssl passwd -6 -stdin
root_password = "$6$rTFai9692MmsAq8I$6y7kogOLaIgjCYwNcMyHmSuMUqXXsU2baJbgkR9d1wuPpwj7Yx8bVhPADOBuHU7qXf.42wVUmyX4y3s4MBtLg/"
reboot_on_error = false

[network]
source = "from-dhcp"
hostname = "pve-srv-1"

[disk]
# Proxmox tries each disk in order and picks the first one it finds
selection = ["nvme0n1", "sda"]
filesystem = "zfs"
zfs.raid = "single"
```

> The `hostname` field here is how Terraform and Ansible files pick up the node name.
> Update it for each node if doing multiple manual installs.

---

## Boot

4. Boot the node from the Ventoy USB
5. On the Proxmox boot menu select **Automated Installation**
6. Wait for the login prompt at `https://IP:8006`

---

## This File Also Lives in Git

The `answer.toml` can be pulled from the IAC repo so you don't have to recreate it:

```sh
git clone https://github.com/itshughboi/homelab-v2.git
```

Look in `bootstrap/` for the per-node TOML files.
