# netboot.xyz

**URL:** https://netboot.hughboi.cc
**Docs:** https://netboot.xyz/docs/

PXE boot server. Lets machines on the LAN boot from the network and select an OS installer or live environment. Used for provisioning new Proxmox nodes and VMs without a USB drive.

## Stack

Single container (LinuxServer image). Runs as `1000:1000`.

## Ports

| Port | Protocol | Purpose |
|---|---|---|
| `69` | UDP | TFTP — **must be open on LAN** for PXE boot to work |
| `3000` | TCP | Web UI (via Traefik) |
| `30000–30010` | TCP | Asset server (for custom menus and assets) |

The TFTP port 69 is bound to all interfaces (`0.0.0.0:69:69/udp`) so that devices on the LAN can reach it. This is intentional — PXE clients broadcast to find the TFTP server.

## Volumes

| Mount | Purpose |
|---|---|
| `config` (named volume) | netboot.xyz config and custom menus |
| `assets` (named volume) | Custom boot assets and ISOs |

## DHCP / BIOS Setup

For PXE to work, the DHCP server (UniFi) must send option 66 (TFTP server) and option 67 (boot filename) to clients:

- **Option 66 (TFTP Server):** `10.10.10.10` (the IP of the Docker host)
- **Option 67 (Bootfile Name):** `netboot.xyz.kpxe` (for legacy BIOS) or `netboot.xyz.efi` (for UEFI)

In UniFi: Networks → [Provisioning Network] → DHCP → Advanced → DHCP Options:
- Code 66, type Text, value `10.10.10.10`
- Code 67, type Text, value `netboot.xyz.kpxe`

## First Run

1. `docker compose up -d`
2. Navigate to https://netboot.hughboi.cc to access the admin UI
3. Configure DHCP options in UniFi as above
4. Boot a test machine from the network — it should get a DHCP lease and load the netboot.xyz menu

## Custom Menus

You can add custom boot entries via the web UI under **Menus**. Custom assets (like locally hosted ISOs) go in the `assets` volume and are served on ports 30000–30010.

## Upgrade Notes

- Config and assets are in named volumes — they survive upgrades.
- After upgrading, the web UI may prompt you to migrate config files — follow the prompts.

## Troubleshooting

**PXE client doesn't get a menu / hangs at boot:**
1. Confirm port 69/UDP is reachable from the client VLAN: `nc -vzu 10.10.10.10 69`
2. Check DHCP options are correctly configured in UniFi
3. Check `docker logs netbootxyz` for TFTP connection attempts

**UEFI boot vs BIOS boot:**
- BIOS (legacy): use `netboot.xyz.kpxe`
- UEFI: use `netboot.xyz.efi`
- Some machines need both options in DHCP if they support both modes
