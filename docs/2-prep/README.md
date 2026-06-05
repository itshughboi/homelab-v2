### SSH Key — Dedicated Datacenter Keypair

Create a separate keypair for the homelab. This gets injected into every node at build time — don't reuse your personal key.

```sh
ssh-keygen -t ed25519 -C "homelab" -f ~/.ssh/homelab_id_ed25519
```

Store the private key locally at first, then put in Vaultwarden once it's running.

### Clone the Repo

> [!NOTE] Gitea is self-hosted — during a fresh rebuild it won't be running yet. Clone from the GitHub mirror:

```sh
git clone https://github.com/itshughboi/homelab-v2.git
cd homelab-v2
```

---

## PXE Netboot

The Libre Potato (10.10.99.99) serves automated Proxmox installs to all nodes via iPXE over VLAN 99. It pulls updates from Git every 5 minutes via a systemd timer.

## Boot Chain

```
Node powers on
    → DHCP (VLAN 99) returns Option 66: 10.10.99.99, Option 67: ipxe.efi
    → Libre Potato serves ipxe.efi over HTTP port 8080
    → iPXE loads, runs autoexec.ipxe → local.ipxe
    → local.ipxe reads node MAC → maps to hostname
    → node pulls its TOML: http://10.10.99.99:8080/proxmox/pve-srv-X.toml
    → Proxmox installs automatically, node receives permanent IP (VLAN 10)
    → Move cable from provisioning port to permanent trunk port
```

## Why netboot.xyz over USB

| Method | Pros | Cons |
| --- | --- | --- |
| netboot.xyz ✅ | No USB juggling, config in Git, fast | Infra must stay healthy |
| Ventoy USB | Works without network | Manual, slow at scale |
| BMC/IPMI | Enterprise break-glass | Requires enterprise hardware |

---

## First-Time Libre Potato Setup

One-time steps to get the netboot server running. Skip if Libre Potato is already serving files or if using Ansible Playbook to install netboot

```sh
git clone https://github.hughboi.cc/itshughboi/homelab-v2.git
cd homelab/bootstrap/netbootxyz
docker compose up -d
```

Go to the web UI at `http://10.10.99.99:3000`, click **Local Assets** along the top, and pull:
- `proxmox-ve initrd`
- `proxmox-ve vmlinuz`

Move the downloaded files into `./assets/proxmox`:

```sh
# Run from bootstrap/netbootxyz
find ./assets/asset-mirror -name "vmlinuz" -exec mv {} ./assets/proxmox/ \;
find ./assets/asset-mirror -name "initrd" -exec mv {} ./assets/proxmox/initrd.img \;
```

> [!NOTE] Add to `.gitignore` before pushing — these are large binaries, download fresh each time:
> ```
> assets/proxmox/vmlinuz
> assets/proxmox/initrd.img
> netbootxyz/assets/asset-mirror/
> !assets/proxmox/.gitkeep
> ```

Restart the container and verify:

```sh
docker compose up -d --force-recreate
curl -I http://10.10.99.99:8080/proxmox/pve-srv-1.toml
```

> [!NOTE] Permission error? `sudo chown -R hughboi:hughboi /opt/iac`

---

## BIOS Prerequisites (every node)

- [ ] PXE boot: **Enabled** (may need to enable "Network Stack" first before this option appears)
- [ ] Boot order: **Network/PXE first**, then NVMe
- [ ] Secure Boot: **OFF**

## Register a Node Before Booting

Three files must be committed and pushed before powering a node on:

**1. Per-node TOML** at `bootstrap/netbootxyz/config/proxmox/pve-srv-X.toml`:

```toml
[global]
keyboard = "us"
timezone = "America/Denver"
# Generate hashed password: printf "yourpassword" | openssl passwd -6 -stdin
root_password = "$6$..."
reboot_on_error = false   # shows errors instead of rebooting in a loop — use this

[network]
source = "from-dhcp"
hostname = "pve-srv-1"   # must match MAC mapping in local.ipxe exactly

[disk]
selection = ["nvme0n1", "sda"]   # tries each in order, installs to first found
filesystem = "zfs"
zfs.raid = "single"              # change to "mirror" if you have 2 disks
```

> [!NOTE]
> `reboot_on_error = false` is critical during initial setup. The installer pauses and shows the error instead of rebooting in a loop, which makes it actually debuggable.

**2. MAC → hostname mapping** in `bootstrap/netbootxyz/config/local.ipxe`:

```
:mac-aabbccddeeff
  set hostname pve-srv-1
  chain http://10.10.99.99:8080/proxmox/pve-srv-1.toml
```

**3. MAC reservation** in UniFi (VLAN 10) so the node gets its permanent IP after install.

Push to Git → Libre Potato picks up changes within 5 minutes.

## Verify Netboot is Serving

Always run this before powering on a node:

```sh
curl -I http://10.10.99.99:8080/ipxe.efi
curl -I http://10.10.99.99:8080/proxmox/pve-srv-1.toml
```

- `200 OK` → good
- `404 Not Found` → file missing from `assets/proxmox/` or path mismatch in `local.ipxe`
- `Connection refused` → container not running — check Docker on Libre Potato

## Boot Procedure

1. Plug node into UXG Max Port 3 (VLAN 99 access port)
2. Power on — watch it PXE boot, pull TOML, install Proxmox (fully automated)
3. Wait for Proxmox login prompt at `https://10.10.10.X:8006`
4. Verify SSH: `ssh root@10.10.10.X`
5. Move cable to permanent trunk port on USW Flex Mini

## Auto-Refresh Timer (Libre Potato)

The git pull timer keeps the Libre Potato current without any SSH access:

```sh
# /etc/systemd/system/netboot-update.service
[Unit]
Description=Update netboot from Git
[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-netboot.sh

# /etc/systemd/system/netboot-update.timer
[Unit]
Description=Check for netboot updates every 5 min
[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
```

```bash
# /usr/local/bin/update-netboot.sh
#!/bin/bash
set -e
sudo -u hughboi git fetch origin main
if sudo -u hughboi git diff --quiet HEAD origin/main -- bootstrap/netbootxyz; then
    echo "No changes in bootstrap/netbootxyz — skipping"
else
    sudo -u hughboi git pull origin main
    cd /opt/iac/bootstrap/netbootxyz
    docker compose up -d
fi
```

Enable: `systemctl enable --now netboot-update.timer`

---

## Fallback Options

### Macbook as Temporary Netboot Server

Use when Libre Potato is down but you still want network-based provisioning. Runs until you close the terminal — no permanent setup needed.

1. Plug Macbook into UXG Max Port 3 (VLAN 99 access port) — it gets assigned `10.10.99.99/24`
2. Run the ephemeral container:

```sh
docker run --rm -it \
  -p 80:80 \
  -p 69:69/udp \
  --name netbootxyz \
  netbootxyz/netbootxyz
```

3. Boot nodes normally — they PXE boot to your Macbook instead of Libre Potato
4. Close the terminal when done — container is automatically removed

> Config files still need to be committed to Git and the container pointed at the right assets path. This is the same boot chain, just served from your laptop temporarily.

### Ventoy USB Fallback {#ventoy-fallback}

Use when Libre Potato is unavailable or you're rebuilding from zero:

1. Format USB with Ventoy
2. Rename main partition to `PROXMOX_AIC` — **required** for the installer to find the answer file
3. Copy Proxmox VE ISO to USB
4. Place `pve-srv-X.toml` renamed to `answer.toml` adjacent to the ISO
5. Boot from USB → select **Automated Installation** from the Proxmox boot menu

---

## Adding a New Node Later

Under 5 minutes of manual work:

1. Copy existing TOML, update: `hostname`, disk selection
2. Add MAC → hostname entry to `local.ipxe`
3. Add MAC reservation in UniFi (VLAN 10)
4. Push to Git — Libre Potato picks up within 5 minutes
5. Plug into UXG Max Port 3, power on
6. After install: move cable to trunk port
7. From Semaphore: run `proxmox/join-cluster` playbook
8. Verify: `pvecm status` shows new node with full votes
