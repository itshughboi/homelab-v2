> [!WARNING] Historical — netboot is abandoned
> Nodes are installed via [Ventoy USB](../../2-proxmox/provisioning/Ventoy.md), not PXE.
> This page documents the old per-node PXE registration flow and is kept for reference
> only. See the [post-mortem](README.md) for why. The per-node TOMLs referenced here are
> still used — Ventoy bakes them into the install ISO instead of serving them over HTTP.

## Register a Node Before Booting

Three things must be in place before powering a node on:

**1. Per-node TOML** at `bootstrap/netbootxyz/assets/proxmox/pve-srv-X.toml`:

```toml
[global]
keyboard = "us"
timezone = "America/Denver"
# Generate hashed password: printf "yourpassword" | openssl passwd -6 -stdin
root_password = "$6$..."
reboot_on_error = false   # shows errors instead of rebooting in a loop — use this

[network]
# Use from-answer — NOT from-dhcp.
# Nodes provision on VLAN 99 (Port 3), which only has DHCP for 10.10.99.x.
# from-dhcp would hardcode a 10.10.99.x address as the management IP.
# from-answer writes the correct management IP directly, regardless of which
# physical VLAN the node is on during installation.
source = "from-answer"
cidr = "10.10.10.X/24"       # replace X with this node's permanent IP
gateway = "10.10.10.254"
dns = "10.10.10.8"
hostname = "pve-srv-X"

[disk]
selection = ["nvme0n1", "sda"]   # tries each in order, installs to first found
filesystem = "zfs"
zfs.raid = "single"              # change to "mirror" if you have 2 disks
```

> [!NOTE]
> `reboot_on_error = false` is critical during initial setup. The installer pauses and shows the error instead of rebooting in a loop, which makes it actually debuggable.

> [!IMPORTANT]
> The node installs with its management IP set statically but is physically on VLAN 99 during that process. The installer does not need internet access — all packages are bundled in the ISO. After install, the node reboots configured for 10.10.10.X but cannot be reached at that address until you move the cable to the trunk port.

---

**2. Per-node MAC boot file** at `bootstrap/netbootxyz/config/menus/MAC-<hexmac>.ipxe`:

When a node PXE boots, the netboot.xyz menu system requests a file named after the node's MAC address via TFTP. If the file exists, it boots directly into the Proxmox automated installer. If not, the interactive netboot.xyz menu appears instead.

Template:

```ipxe
#!ipxe
# pve-srv-X — MAC xx:xx:xx:xx:xx:xx
set base http://${next-server}:8080
imgfree
kernel ${base}/proxmox/vmlinuz vga=791 video=vesafb:ywrap,mtrr ramdisk_size=16777216 rw quiet splash=silent proxmox-installer-opts=mode=auto,url=${base}/proxmox/pve-srv-X.toml initrd=initrd.magic
initrd ${base}/proxmox/initrd.img
initrd ${base}/asset-mirror/releases/download/9.1-1-1d6923a5/proxmox.iso /proxmox.iso
boot
```

The MAC in hex, no colons, lowercase — e.g. `c8:ff:bf:03:f3:50` → `MAC-c8ffbf03f350.ipxe`.

> [!IMPORTANT]
> **Do not create this file with `sudo`**. Files created with `sudo tee` or `sudo cp` get
> `root:root` ownership. The TFTP server (dnsmasq) runs as UID 1000 inside the container
> and cannot read root-owned files — you will see `Permission denied` in the container logs
> and the node falls back to the interactive menu.
>
> Create the file as your normal user (or via `git pull` which sets ownership automatically).
> If you already created it with sudo: `sudo chown 1000:1000 <file> && sudo chmod 755 <file>`

> [!NOTE]
> The ISO path in `initrd` includes a version hash (`9.1-1-1d6923a5`). When you download
> a newer Proxmox ISO via Local Assets, update this path in each MAC file to match.
> Check the current path: `find ./assets/asset-mirror -name "proxmox.iso" -type f`

---

**3. MAC reservation** in UniFi (VLAN 10) so the node gets its permanent IP after install — see [MAC Reservations.md](../Unifi/Assignments/MAC%20Reservations.md).

Push to Gitea → Libre Potato picks up changes within 5 minutes (systemd timer runs `git pull` and restarts the container if anything in `bootstrap/netbootxyz` changed).

---

## Verify Netboot is Serving

Always run this before powering on a node:

```sh
curl -I http://10.10.99.99:8080/proxmox/pve-srv-4.toml     # answer file
curl -I http://10.10.99.99:8080/proxmox/vmlinuz              # kernel
curl -I http://10.10.99.99:8080/proxmox/initrd.img           # initrd
# Check ISO path matches what's in the MAC file:
find /opt/iac/bootstrap/netbootxyz/assets/asset-mirror -name "proxmox.iso" -type f
```

- `200 OK` → good
- `404 Not Found` → file missing or path mismatch
- `Connection refused` → container not running — `docker compose ps`

---

## Boot Procedure

1. Plug node into UXG Max Port 3 (VLAN 99 access port)
2. Power on — UEFI downloads `netboot.xyz.efi` via TFTP, iPXE starts
3. iPXE loads the node's MAC file → downloads vmlinuz, initrd, and proxmox.iso → automated Proxmox install begins (~5–10 min, no interaction needed)
4. Node reboots after install — it is now configured for `10.10.10.X` but still on VLAN 99 → not reachable yet
5. **Move cable to permanent trunk port on USW Flex Mini**
6. Wait ~30 seconds for the node to finish booting on the management VLAN
7. Access Proxmox web UI: `https://10.10.10.X:8006`
8. Verify SSH: `ssh root@10.10.10.X`

---

## Adding a New Node Later

Under 5 minutes of manual work:

1. Copy existing TOML, update: `hostname`, `cidr`, disk selection
2. Create `config/menus/MAC-<hexmac>.ipxe` (as your normal user, not sudo), update TOML filename
3. Add MAC reservation in UniFi (VLAN 10)
4. Push to Gitea — Libre Potato picks up within 5 minutes
5. Plug into UXG Max Port 3, power on
6. After install: move cable to trunk port
7. From Semaphore: run `proxmox/join-cluster` playbook
8. Verify: `pvecm status` shows new node with full votes
