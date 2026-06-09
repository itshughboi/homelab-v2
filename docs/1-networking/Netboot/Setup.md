## First-Time Libre Potato Setup

One-time steps to get the netboot server running. Skip if Libre Potato is already serving files.

### Step 0 — Set a Static IP

Do this before anything else. The netboot server must always be at `10.10.99.99` — DHCP is unreliable for infrastructure, and the entire provisioning flow points at this address.

Port 2 on the UXG Max has VLAN 99 as its native VLAN, so the Libre Potato is on the provisioning subnet on first boot.

```sh
# Write static IP config — interface is eth0 on this hardware
sudo tee /etc/netplan/01-static.yaml << 'EOF'
network:
  version: 2
  ethernets:
    eth0:
      addresses:
        - 10.10.99.99/24
      routes:
        - to: default
          via: 10.10.99.254
      nameservers:
        addresses: [9.9.9.9, 1.1.1.1]
EOF

# Netplan requires 600 permissions
sudo chmod 600 /etc/netplan/01-static.yaml

# Disable cloud-init network management so it doesn't overwrite this on reboot
sudo bash -c 'echo "network: {config: disabled}" > /etc/cloud/cloud.cfg.d/99-disable-network.cfg'

# Delete any cloud-init generated netplan file — it would override 01-static.yaml
# (alphabetically later = higher priority in netplan)
sudo rm -f /etc/netplan/50-cloud-init.yaml

sudo netplan apply
```

> [!NOTE]
> If you can't reach it (e.g., after changing the switch port native VLAN), temporarily flip port 2 back to VLAN 10 native in UniFi → SSH in → run the above → flip port back to VLAN 99 native.

---

### Step 1 — Clone and Start

```sh
git clone https://gitea.hughboi.cc/hughboi/homelab.git /opt/iac
cd /opt/iac/bootstrap/netbootxyz
docker compose up -d
```

Go to the web UI at `http://10.10.99.99:3000`, click **Local Assets** along the top, and pull:
- `proxmox-ve vmlinuz`
- `proxmox-ve initrd`
- `proxmox-ve iso` — the full ISO is required; the installer uses it as installation media

Move the downloaded files into `./assets/proxmox`:

```sh
# Run from bootstrap/netbootxyz
find ./assets/asset-mirror -name "vmlinuz" -exec mv {} ./assets/proxmox/ \;
find ./assets/asset-mirror -name "initrd" -exec mv {} ./assets/proxmox/initrd.img \;
```

The ISO stays in its asset-mirror path — the MAC boot files reference it there directly. Check the path:

```sh
find ./assets/asset-mirror -name "proxmox.iso" -type f
# e.g. ./assets/asset-mirror/releases/download/9.1-1-1d6923a5/proxmox.iso
```

Verify the version hash in the path matches what's in `config/menus/MAC-*.ipxe`. If you downloaded a newer ISO than what the MAC files reference, update the path in each MAC file.

> [!NOTE]
> Add to `.gitignore` before pushing — these are large binaries, download fresh each time:
> ```
> assets/proxmox/vmlinuz
> assets/proxmox/initrd.img
> assets/asset-mirror/
> ```

Restart and verify:

```sh
docker compose up -d --force-recreate
curl -I http://10.10.99.99:8080/proxmox/pve-srv-1.toml
curl -I http://10.10.99.99:8080/proxmox/vmlinuz
```

> [!NOTE] Permission error? `sudo chown -R hughboi:hughboi /opt/iac`

---

## File Ownership — Critical

The TFTP server (dnsmasq) runs inside the container as UID 1000. Files created with `sudo` get `root:root` ownership and **cannot be read by dnsmasq**, causing silent `Permission denied` failures in the logs.

- Files from `git pull` → correct ownership automatically (git checks out as the current user)
- Files copied with `sudo cp` or `sudo tee` → wrong ownership
- Fix: `sudo chown 1000:1000 <file> && sudo chmod 755 <file>`

This applies to everything in `config/menus/`. Prefer `git pull` over manual file creation.

---

## Auto-Refresh Timer

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
