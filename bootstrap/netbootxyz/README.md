# netboot.xyz PXE Boot Server

> [!WARNING] Deprecated — no longer active
> This PXE setup was abandoned in favour of [Ventoy USB](../../docs/2-proxmox/provisioning/Ventoy.md);
> see the [post-mortem](../../docs/1-networking/Alternative%20Methods/Netboot/README.md) for the full reasoning.
> The compose stack, `local.ipxe`, and `config/menus/*.ipxe` here are inactive and kept only
> as reference. The per-node answer TOMLs that used to live in `assets/proxmox/` have moved to
> [`../ventoy/answers/`](../ventoy/answers/) — the live Ventoy path consumes them there.

Serves a PXE environment that fully automates Proxmox installation on bare-metal servers — no USB stick, no manual clicks. Boot a new server, walk away, come back to a configured Proxmox node.

---

## Boot chain

```
New server powers on
   │
   ├─ BIOS/UEFI requests PXE
   │
   ▼
DHCP server (UniFi)
   ├─ Issues IP lease
   ├─ Option 66 (next-server) → IP of the machine running netboot.xyz
   └─ Option 67 (filename)    → netboot.xyz iPXE binary (e.g. ipxe.efi or undionly.kpxe)
   │
   ▼
netboot.xyz TFTP (port 69)
   └─ Sends iPXE binary to client
   │
   ▼
iPXE binary runs on client
   └─ Fetches autoexec.ipxe via HTTP from the assets server (port 8080)
      └─ config/menus/autoexec.ipxe
         └─ chains to http://${next-server}:8080/proxmox/local.ipxe
   │
   ▼
config/local.ipxe
   ├─ Reads MAC address → maps to hostname (pve-srv-1 .. pve-srv-4)
   └─ Boots Proxmox kernel + initrd with:
      proxmox-autoinstall-mode=http
      proxmox-autoinstall-url=http://${next-server}:8080/proxmox/${hostname}.toml
   │
   ▼
assets/proxmox/${hostname}.toml
   └─ Proxmox autoinstaller reads preseed: disk layout, network, hostname, root password, SSH keys
   │
   ▼
Proxmox installed and running on the node
```

---

## Directory layout

```
netbootxyz/
├── compose.yaml                  # Docker Compose — runs the netboot.xyz container
├── config/
│   ├── local.ipxe                # MAC → hostname mapping; boots Proxmox kernel
│   └── menus/
│       └── autoexec.ipxe         # Entry point: chains to local.ipxe
└── assets/
    └── proxmox/
        ├── vmlinuz               # Proxmox installer kernel  (you supply this)
        ├── initrd.img            # Proxmox installer initrd  (you supply this)
        ├── pve-srv-1.toml        # Preseed for pve-srv-1
        ├── pve-srv-2.toml        # Preseed for pve-srv-2
        ├── pve-srv-3.toml        # Preseed for pve-srv-3
        └── pve-srv-4.toml        # Preseed for pve-srv-4
```

---

## Initial setup

### 1. Get the Proxmox installer kernel and initrd

Download from the Proxmox ISO (or use the official netboot artifacts):

```bash
# Mount the Proxmox VE ISO and copy the netboot files
# Replace with the actual Proxmox VE ISO version you want to install
iso="proxmox-ve_8.x-x.iso"
mount -o loop "$iso" /mnt/iso
cp /mnt/iso/boot/linux26   bootstrap/netbootxyz/assets/proxmox/vmlinuz
cp /mnt/iso/boot/initrd.img bootstrap/netbootxyz/assets/proxmox/initrd.img
umount /mnt/iso
```

Alternatively, extract them with `7z` or `bsdtar` without mounting:

```bash
7z e "$iso" boot/linux26 boot/initrd.img -o assets/proxmox/
mv assets/proxmox/linux26 assets/proxmox/vmlinuz
```

### 2. Configure DHCP in UniFi

In UniFi Network → Networks → select the provisioning VLAN (VLAN 10) → DHCP → Advanced:

| Option | Value |
|--------|-------|
| TFTP Server (option 66) | IP of the host running netboot.xyz (e.g. `10.10.10.50`) |
| Boot File (option 67) | `netboot.xyz.efi` for UEFI, `netboot.xyz-undionly.kpxe` for legacy BIOS |

The container exposes TFTP on port 69 — it serves these files automatically.

### 3. Start the container

```bash
cd bootstrap/netbootxyz
docker compose up -d
```

Ports exposed:
- `3000` — netboot.xyz web UI (menu customisation, TFTP monitoring)
- `69/udp` — TFTP server (PXE clients download the iPXE binary here)
- `8080` — HTTP server (serves `config/` and `assets/` to booting clients)

---

## Adding a new server

1. **Get the MAC address** of the server's primary NIC (from BIOS/UEFI, IPMI, or a live boot).

2. **Add a MAC → hostname mapping** in `config/local.ipxe`:
   ```ipxe
   iseq ${net0/mac} aa:bb:cc:dd:ee:ff && set hostname pve-srv-5 ||
   ```

3. **Create a preseed file** `assets/proxmox/pve-srv-5.toml` — copy an existing `.toml` and update:
   - `hostname` and `fqdn`
   - `address` (static IP)
   - Keep `root_password` and `ssh_public_keys` the same unless you want per-host keys

4. Boot the server. No container restart required — files are served live from the bind-mounted `assets/` directory.

---

## Preseed files (`.toml`)

Each `assets/proxmox/pve-srv-N.toml` is a Proxmox autoinstall answer file. Key sections:

### `[global]`
- `root_password` — SHA-512 hashed. Generate with: `openssl passwd -6 "YourPassword"`
- `ssh_public_keys` — list of authorized public keys for root. Two keys are present: the operator's RSA key and the `ansible` ed25519 key (used by Ansible playbooks).

### `[network]`
- `source = "from-answer"` — use the values in this file, not DHCP
- `gateway = "10.10.10.254"` — this is the gateway for VLAN 10 as configured in UniFi. The Proxmox nodes use `10.10.10.1-4` but their gateway is `.254` (the router).

### `[disk-setup]`
- `filter.ID_TYPE = "disk"` — selects all block devices that identify as a disk (excludes USB, optical, etc.)
- `disk_list = []` — an **empty list means use all disks matching the filter**. Proxmox will use every drive it finds. If a server has multiple drives and you only want one used for the OS, list it explicitly:
  ```toml
  disk_list = ["/dev/sda"]
  ```

---

## Troubleshooting

**Server doesn't PXE boot at all**
- Confirm PXE is enabled in BIOS/UEFI and is first in boot order
- Check DHCP options 66/67 are set correctly in UniFi
- Verify the netboot.xyz container is running: `docker compose ps`

**Server gets iPXE but hangs / wrong menu**
- Check `autoexec.ipxe` is being served: `curl http://<host-ip>:8080/proxmox/local.ipxe`
- Confirm the MAC address in `local.ipxe` matches the server's actual MAC exactly (lowercase, colon-separated)
- If no MAC matches, `${hostname}` will be empty and the kernel boot will fail

**Proxmox autoinstall fails / wrong config applied**
- Verify the `.toml` is reachable: `curl http://<host-ip>:8080/proxmox/pve-srv-N.toml`
- Check `root_password` hash is valid (test with `openssl passwd -6 -verify "$hash"`)
- Review installer logs on the server console

**"No such file" for vmlinuz / initrd.img**
- These are not included in the repo — extract them from the Proxmox ISO (see setup step 1 above)

---

## Teardown

Once all Proxmox nodes are installed and reachable, stop and remove the container:

```bash
cd bootstrap/netbootxyz
docker compose down
```

The container has no persistent state beyond `config/` and `assets/` which remain in the repo. It can be restarted at any time to provision additional hardware.
