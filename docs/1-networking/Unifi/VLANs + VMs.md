
| Name         | VLAN | CIDR           | Gateway       | Notes                                                                       |
| ------------ | ---- | -------------- | ------------- | --------------------------------------------------------------------------- |
| Management   | 10   | 10.10.10.0/24  | 10.10.10.254  | SSH, Web UI, Unifi, Bind9. PXE boot enabled.                                |
| Cluster      | 20   | 10.10.20.0/24  | None          | Corosync heartbeat only. No gateway. QoS enabled. **DHCP disabled.**        |
| k3s          | 30   | 10.10.30.0/24  | 10.10.30.254  | All nodes use static IPs via cloud-init. **DHCP pool starts at .200.**      |
| Storage      | 40   | 10.10.40.0/24  | 10.10.40.254  | Jumbo Frames (MTU 9000). Outbound updates only. **DHCP disabled.**          |
| IoT          | 50   | 10.10.50.0/24   | 10.10.50.254  | Smart home devices. Isolated — only Home Assistant can initiate into IoT.   |
| Torrent      | 49   | 172.16.20.0/24  | 172.16.20.254 | UNTRUSTED. Fully airgapped from internal network.                           |
| VPN          | 80   | 10.10.80.0/24   | 10.10.80.254  | Tailscale subnet router. Full VLAN access for VPN users.                    |
| Guest        | —    | 172.69.69.0/24  | 172.69.69.254 | AP guest WiFi. Isolated, client isolation, internet only. Auto DHCP.        |
| Provisioning | 99   | 10.10.99.0/24   | 10.10.99.254  | Short lease time. Nodes live here only during install.                      |

> [!IMPORTANT]
> **VLAN 20 (Cluster) and VLAN 40 (Storage): DHCP must be disabled.**
> Cluster is Corosync-only at the host level — no device should ever DHCP here.
> Storage devices all have static IPs — a rogue client on VLAN 40 could reach NFS/PBS.
> Disable in UniFi → Networks → [VLAN] → DHCP Mode → None.
>
> **VLAN 30 (k3s): DHCP pool was .1–.20 which directly overlapped static node IPs.**
> Masters (.1–.3), workers (.11–.13), kube-vip (.30), Longhorn (.50–.53), MetalLB (.60–.99)
> all live in the lower range. Pool moved to .200–.220. Update in UniFi immediately.

#### DHCP
| Name         | Start         | End           | Notes                                              |
| ------------ | ------------- | ------------- | -------------------------------------------------- |
| Management   | 10.10.10.100  | 10.10.10.200  |                                                    |
| Cluster      | —             | —             | **Disabled** — Corosync only, no DHCP clients      |
| k3s          | 10.10.30.200  | 10.10.30.220  | Moved above static/MetalLB range (was .1–.20 ⚠️)  |
| Storage      | —             | —             | **Disabled** — all devices have static IPs         |
| IoT          | 10.10.50.10   | 10.10.50.200  | Smart home devices receive dynamic IPs             |
| Guest        | Auto          | Auto          | UniFi manages automatically                        |
| Torrent      | 172.16.20.1   | 172.16.20.20  |                                                    |
| Tailscale    | 10.10.80.1    | 10.10.80.20   |                                                    |
| Wireguard    | 10.10.81.1    | 10.10.81.20   | Clients receive IPs from this range when connected |
| Provisioning | 10.10.99.1    | 10.10.99.200  |                                                    |

---

#### mDNS Forwarding

mDNS forwarding allows device discovery to cross VLAN boundaries. **Off by default in UniFi — only enable where explicitly needed.**

| Network | mDNS | Reason |
| ------- | ---- | ------ |
| Management (10) | Off | Proxmox/Athena don't use mDNS |
| Cluster (20) | Off | Corosync only |
| k3s (30) | **On** | Home Assistant discovers IoT devices across VLAN boundary |
| Storage (40) | Off | TrueNAS/PBS don't need it |
| IoT (50) | **On** | HA ↔ IoT device discovery |
| Torrent (49) | Off | Airgapped |
| VPN (80) | Off | Tailscale handles its own discovery |
| Guest | Off | Guests must not discover internal or IoT devices |
| Provisioning (99) | Off | Temporary network |

> [!NOTE]
> When adding a new network in UniFi, mDNS forwarding defaults to **off**. Only enable it on the specific pair of networks that need cross-VLAN discovery. Leaving it on unnecessarily widens your attack surface — a compromised guest device could discover and probe IoT devices.

---

### Per-VLAN Notes

###### VLAN 10 — Management
The admin plane. Reaches everything. Nothing initiates into it (firewall enforces this).
Core services that live here: Unifi controller, Proxmox web UI, Docker host, Ansible (Athena), Bind9.

###### VLAN 20 — Cluster (Corosync)
Corosync is extremely sensitive to latency. If a NIC gets flooded with backup or storage traffic,
jitter can trigger a **Fencing event (hard reboot)** of a Proxmox node.

VLAN 20 exists at the Proxmox host level only — no VMs attach to it.

**NO GATEWAY** — internal routing only.

Settings:
- **IGMP Snooping enabled** — prevents Corosync multicast from flooding all switch ports
- **QoS:** Tag traffic on UDP 5404–5405 with DSCP 46 (Expedited Forwarding)

###### VLAN 30 — k3s
Nodes pull from internet, access storage, talk to each other. Cannot initiate to Management.
See firewall rules for specifics.

###### VLAN 40 — Storage
TrueNAS, PBS, and Longhorn traffic. PBS or Longhorn can saturate the management NIC —
this VLAN exists specifically to isolate that traffic.

**Has gateway (`10.10.40.254`) for outbound package updates only. Firewall restricts all other outbound.**

Settings:
- **Jumbo Frames (MTU 9000)**

> [!DANGER] Jumbo Frames — MTU must be 9000 end-to-end
> Every device on VLAN 40 must be configured for MTU 9000:
> - Switch ports
> - Physical NICs
> - Proxmox bridges (vmbr)
> - Proxmox physical interface (e.g. enp42s0)
> - VMs (if applicable)
>
> Partial MTU 9000 support causes **silent packet loss**. Jumbo packets cannot
> traverse the internet — this VLAN is internal-only by design.

###### VLAN 50 — IoT

Smart home devices: Zigbee coordinator, Z-Wave, smart plugs, lights, sensors, cameras.
These devices often run outdated firmware with known CVEs and cannot be patched regularly.
Isolating them prevents any compromised device from reaching infrastructure.

**Home Assistant is the only service allowed to initiate connections into this VLAN.**
IoT devices cannot initiate connections out to any internal network — only to the internet
for cloud APIs and updates.

**IoT WiFi SSID:** Create a dedicated SSID in UniFi on VLAN 50. Keep it separate from
your main WiFi. Devices on the IoT SSID never see your laptop or management hosts.

**mDNS/Bonjour bridging:** Home Assistant needs mDNS to discover local devices (Chromecast,
Apple TV, etc.). Enable mDNS forwarding in UniFi between VLAN 30 (k3s) and VLAN 50 (IoT)
or run an Avahi mDNS reflector on Athena.

Settings:
- DHCP enabled (.10–.200)
- Short lease time (4–8 hours) — IoT devices reconnect frequently
- Block inter-VLAN: ON (baseline)
- mDNS forwarding: ON (for Home Assistant discovery)

###### VLAN 49 — Torrent
Fully airgapped from the internal network. WAN access only.
gluetun (VPN killswitch), qBittorrent, Soularr live here.

> RFC1918 block required in firewall. UniFi doesn't have a built-in RFC1918 alias —
> create an IP group covering `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`.

###### VLAN 80 — Tailscale
Tailscale subnet router only. VPN users get scoped access to Management, k3s, and Storage.
Zone: `Tailscale`. See firewall rules for exact permissions.

###### VLAN 81 — Wireguard
UniFi WireGuard VPN server. Fallback remote access for devices that can't run Tailscale.
Zone: `Wireguard`. Requires public IP or DDNS. See [VPN.md](VPN.md) for setup.

###### VLAN 99 — Provisioning
Temporary. Nodes live here only during Proxmox installation, then move to Management.
Short DHCP lease time. Libre Potato is the only permanent resident.

---

### Single NIC Performance Note (pve-srv-1)

TrueNAS and PBS are dual-homed on VLAN 10 (Management) and VLAN 40 (Storage),
but both share the same physical 2.5 GbE NIC via 802.1Q tagging on vmbr1.

There is no physical bandwidth isolation between management and storage traffic.
In practice: heavy NFS/backup activity can saturate the NIC, and SSH/Web UI on
VLAN 10 will feel it.

This is acceptable for a homelab. The fix, when needed, is a dedicated second NIC
for VLAN 40 — no VLAN config changes needed, just move vmbr1.40 to the new interface.


#### VM Overview

| VM        | Host      | VLAN  | RAM   | CPU | Notes                                      |
| --------- | --------- | ----- | ----- | --- | ------------------------------------------ |
| unifi     | pve-srv-1 | 10    | 2GB   | 2   | Controller only, LXC                       |
| athena    | pve-srv-1 | 10    | 8GB   | 4   | Ansible, OpenTofu, Bind9, Gitea, Semaphore |
| docker    | pve-srv-1 | 10    | 24GB  | 4   | Docker + Traefik + application workloads   |
| truenas   | pve-srv-1 | 10/40 | 32GB  | 4   | Dual-homed, drives passed through          |
| pbs       | pve-srv-1 | 10/40 | 4GB   | 2   | Dual-homed, NFS datastore on TrueNAS       |
| tailscale | pve-srv-1 | 80    | 512MB | 1   | Subnet router only                         |
| master-1  | pve-srv-2 | 30    | 4GB   | 2   | Control plane, tainted NoSchedule          |
| worker-1  | pve-srv-2 | 30/40 | 24GB  | 6   | Workloads + Longhorn, 500GB SSD            |
| master-2  | pve-srv-3 | 30    | 4GB   | 2   | Control plane, tainted NoSchedule          |
| worker-2  | pve-srv-3 | 30/40 | 24GB  | 6   | Workloads + Longhorn, 500GB SSD            |
| master-3  | pve-srv-4 | 30    | 4GB   | 2   | Control plane, tainted NoSchedule          |
| worker-3  | pve-srv-4 | 30/40 | 24GB  | 6   | Workloads + Longhorn, 500GB SSD            |
| netboot   | dedicated | 99    | —     | —   | Libre Potato, bare metal                   |

> [!NOTE] Athena — Why everything lives here
> Athena is the management plane. Gitea and Semaphore live here rather than
> on the Docker host to avoid a bootstrap chicken-and-egg problem — Traefik
> (on Docker) can't be up before Semaphore, but Semaphore is needed to bring
> Traefik up. Athena is reachable by IP directly during bootstrap, then gets
> a subdomain via Traefik later once it's running.
>
> Gitea is configured with GitHub push mirroring — every push to Gitea
> automatically mirrors to GitHub as an offsite backup. Netboot also points
> to the public GitHub repo as a fallback.

