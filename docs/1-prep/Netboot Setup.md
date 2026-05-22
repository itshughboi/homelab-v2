
> Skip this section if using the Ansible bootstrap playbook — it handles this automatically.

---

### My Pick
- In this setup I am using *netbootxyz* on my macbook. Could also be dedicated box
	- Plug macbook into the provisioning port on my Unifi switch. It will be assigned IP of **10.10.99.100/24** on VLAN **99**
	- If not using Unifi, or DHCP Boot options not setup, ssh/console into router to set those options. See here: [[Guide]]
	- Make sure that devices have PXE boot enabled in BIOS
		- I had to go into Network Stack: Enabled before I could enable PXE boot
	

##### Quick:
**Assets**: 
- proxmox-ve iso
- proxmox-ve initrd (Contains proxmox installer environment)
- proxmox-ve vmlinuz (installer kernel. PXE loads this first)
- answer.toml (actual config for unattended installer)

1. Run this to spin up ephemeral netboot container (runs as long as terminal is open)
	
```sh
docker run --rm -it \
  -p 80:80 \
  -p 69:69/udp \
  --name netbootxyz \
  netbootxyz/netbootxyz
```

2. Power on server nodes. They boot via iPXE, redirect to my Macbook running the modified netbootxyz to auto install Proxmox over HTTP




*** 
### Troubleshooting
**Permission**: If I get permission denied, need to go onto netbootxyz host and do the following:
```sh
sudo chown -R 1000:1000 /opt/homelab/bootstrap/netbootxyz
```
and then reboot




## Initial Setup

1. Pull down the IAC repo and stand up the netboot container:
```sh
git clone https://github.com/itshughboi/homelab-v2.git
cd homelab-v2/bootstrap/netbootxyz
docker compose up -d
```

2. Go to the web UI at `http://10.10.99.99:3000`
3. Click **Local Assets** along the top
4. Pull the following assets:
   - `proxmox-ve initrd`
   - `proxmox-ve vmlinuz`

5. Move downloaded files into `./assets/proxmox`:
```sh
# Run from bootstrap/netbootxyz — uses relative paths

# Move vmlinuz
find ./assets/asset-mirror -name "vmlinuz" -exec mv {} ./assets/proxmox/ \;

# Move and rename initrd
find ./assets/asset-mirror -name "initrd" -exec mv {} ./assets/proxmox/initrd.img \;
```

> [!NOTE] One-time repo setup — add these to `.gitignore` before pushing:
> ```
> # Heavy binary blobs — download fresh each time
> assets/proxmox/vmlinuz
> assets/proxmox/initrd.img
>
> # Netboot mirror cache
> netbootxyz/assets/asset-mirror/
>
> # Keep proxmox folder in git but empty
> !assets/proxmox/.gitkeep
> ```

6. Restart the container:
```sh
docker compose up -d --force-recreate
```

7. Verify assets are being served:
```sh
curl -I http://10.10.99.99:8080/proxmox/pve-srv-1.toml
```

> [!NOTE] Permission error?
> ```sh
> sudo chown -R hughboi:hughboi /opt/iac
> ```

---

## Git Pull Auto-Refresh

Watches for changes to `bootstrap/netbootxyz` in GitHub every 5 minutes
and redeploys the container only if those files changed. Editing unrelated
files in the repo won't trigger a restart.

> [!NOTE]
> This is a stopgap until a proper GitHub Actions runner is set up for automated deploys.

**1. Create the service file:**
```sh
sudo nano /etc/systemd/system/netboot-update.service
```
```ini
[Unit]
Description=Update netboot from Git

[Service]
Type=oneshot
ExecStart=/usr/local/bin/update-netboot.sh
```

**2. Create the timer:**
```sh
sudo nano /etc/systemd/system/netboot-update.timer
```
```ini
[Unit]
Description=Run netboot update every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
```

**3. Create the update script:**
```sh
sudo nano /usr/local/bin/update-netboot.sh
```
```bash
#!/bin/bash
set -e

sudo -u hughboi git fetch origin main

if sudo -u hughboi git diff --quiet HEAD origin/main -- bootstrap/netbootxyz; then
    echo "No changes in bootstrap/netbootxyz. Skipping deploy."
else
    echo "Changes detected. Updating..."
    sudo -u hughboi git pull origin main
    cd /opt/iac/bootstrap/netbootxyz
    docker compose up -d
fi
```

**4. Make executable and enable:**
```sh
sudo chmod +x /usr/local/bin/update-netboot.sh
sudo systemctl daemon-reload
sudo systemctl enable --now netboot-update.timer
```

**5. Test manually:**
```sh
/usr/local/bin/update-netboot.sh
```
