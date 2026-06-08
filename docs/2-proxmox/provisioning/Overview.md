# Provisioning Overview

> The netboot container is configured via Ansible playbook on first run.
> Container lives at `/opt/homelab/bootstrap/netbootxyz` on `10.10.99.99`.

---

## Why PXE / Netbootxyz

Four approaches exist for bare-metal provisioning. This homelab uses **netbootxyz** (classic PXE):

| Method | How It Boots | Best For |
| --- | --- | --- |
| **Classic PXE / Netboot** ✅ | DHCP → iPXE → Installer (answer.toml) | Homelabs, flexible, no vendor lock-in |
| Image-Based | PXE → disk imaging agent → reboot | Datacenters, k8s fleets — faster but more complex |
| BMC / IPMI / Redfish | API → mount ISO → autoinstall | Enterprises, break-glass recovery |
| Bare-Metal-as-a-Service | Provider-controlled | Hyperscalers |

PXE pros for this use case: simple, cheap, flexible, no vendor lock-in.
PXE cons: slower at scale, PXE infra (Libre Potato) must stay healthy.

---

## Boot Chain

```
ipxe.efi (DHCP Option 67)
    ↓
local.ipxe (iPXE script — reads node MAC)
    ↓
pve-srv-X.toml (per-node answer file)
    ↓
Proxmox automated install
```

DHCP hands the node `ipxe.efi` which bootstraps iPXE. iPXE then runs `local.ipxe`,
reads the node's MAC, and pulls the correct per-node TOML to drive the automated install.

---

## BIOS Prerequisites (per node)

1. PXE boot enabled (may need to enable **Network Stack** first before PXE option appears)
2. Boot order set to **PXE first**
3. Secure Boot **OFF**

---

## Provisioning Flow

1. Plug node into **UXG Max port 3** (dedicated VLAN 99 access port)
2. Power on — DHCP assigns a `10.10.99.x` address and returns:
   - Option 66: `10.10.99.99` (boot server)
   - Option 67: `ipxe.efi` (boot filename, served via HTTP)
3. Node downloads `ipxe.efi` from `http://10.10.99.99:8080/ipxe.efi`
4. iPXE loads, runs `local.ipxe`, identifies node by MAC address
5. Node pulls its specific TOML: `http://10.10.99.99:8080/proxmox/pve-srv-X.toml`
6. Proxmox installs and configures automatically
7. Node receives its permanent IP via MAC reservation on VLAN 10
8. Move cable from port 3 to permanent trunk port on USW Flex Mini
9. Athena can now reach it on VLAN 10

> [!IMPORTANT] HTTP not TFTP
> UniFi serves `ipxe.efi` via HTTP by default in newer firmware, not TFTP.
> The netboot container must be serving on port 8080 over HTTP. TFTP-only
> setups will silently fail at the binary download step.

---

## Verify Netboot is Serving

```sh
curl -I http://10.10.99.99:8080/ipxe.efi
curl -I http://10.10.99.99:8080/proxmox/pve-srv-2.toml
```

Expected: `HTTP/1.1 200 OK` on both.

- `404 Not Found` — file not in `./assets/proxmox` or mapping wrong
- `Connection refused` — container not running or firewall blocking 8080

---

## Adding a New Node

1. Copy an existing `.toml` file, update hostname, MAC, and IP values
2. Add the new node's MAC and hostname mapping to `local.ipxe`
3. Add MAC reservation in UniFi for VLAN 10
4. Push to Gitea — the git pull timer picks it up within 5 minutes (mirrors to GitHub automatically)
5. Plug new node into port 3 and power on
6. After install: move cable to permanent trunk port on USW Flex Mini

---

## Troubleshooting

**Permission denied on netboot host:**
```sh
sudo chown -R 1000:1000 /opt/homelab/bootstrap/netbootxyz
```
Then reboot the container.

**PXE boots but wrong node config loads:**
Check MAC mapping in `local.ipxe` — the MAC must match exactly.
