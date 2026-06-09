
| Name         | VLAN | CIDR           | Gateway       | Notes                                                                     |
| ------------ | ---- | -------------- | ------------- | ------------------------------------------------------------------------- |
| Management   | 10   | 10.10.10.0/24  | 10.10.10.254  | SSH, Web UI, Unifi, Bind9. Nodes install directly onto this VLAN.          |
| Cluster      | 20   | 10.10.20.0/24  | None          | Corosync heartbeat only. No gateway. QoS enabled. **DHCP disabled.**      |
| k3s          | 30   | 10.10.30.0/24  | 10.10.30.254  | All nodes use static IPs via cloud-init. **DHCP disabled.**               |
| Storage      | 40   | 10.10.40.0/24  | None          | Jumbo Frames (MTU 9000). Internal only. **DHCP disabled.**                |
| Torrent      | 49   | 172.16.20.0/24 | 172.16.20.254 | UNTRUSTED. Fully airgapped from internal network.                         |
| IoT          | 50   | 10.10.50.0/24  | 10.10.50.254  | Smart home devices. Isolated — only Home Assistant can initiate into IoT. |
| Guest        | 69   | 172.69.69.0/24 | 172.69.69.254 | AP guest WiFi. Isolated, client isolation, internet only. Auto DHCP.      |
| VPN          | 80   | 10.10.80.0/24  | 10.10.80.254  | Tailscale subnet router. Full VLAN access for VPN users.                  |
| WireGuard    | 81   | 10.10.81.0/24  | 10.10.81.254  | UniFi WireGuard VPN server. Fallback remote access. Requires public IP.   |
| Provisioning | 99   | 10.10.99.0/24  | 10.10.99.254  | Legacy netboot VLAN — unused since provisioning moved to Ventoy USB.       |

> [!IMPORTANT]
> **VLANs 20, 30, 40: DHCP must be disabled.**
> All devices on these VLANs have static IPs (cloud-init for k3s, host-level config for Cluster/Storage). A rogue DHCP client on any of these could grab an IP already in use by a node, MetalLB service, or storage device.
> Disable in UniFi → Networks → [VLAN] → DHCP Mode → None.

#### DHCP
| Name         | Start        | End          | Notes                                                   |
| ------------ | ------------ | ------------ | ------------------------------------------------------- |
| Management   | 10.10.10.100 | 10.10.10.200 |                                                         |
| Cluster      | —            | —            | **Disabled** — Corosync only, no DHCP clients           |
| k3s          | —            | —            | **Disabled** — all nodes have static IPs via cloud-init |
| Storage      | —            | —            | **Disabled** — all devices have static IPs              |
| Torrent      | 172.16.20.10 | 172.16.20.20 |                                                         |
| IoT          | 10.10.50.10  | 10.10.50.200 | Smart home devices receive dynamic IPs                  |
| Guest        | Auto         | Auto         | UniFi manages automatically                             |
| Tailscale    | 10.10.80.10  | 10.10.80.20  |                                                         |
| Wireguard    | 10.10.81.10  | 10.10.81.20  | Clients receive IPs from this range when connected      |
| Provisioning | 10.10.99.100 | 10.10.99.200 |                                                         |

---

#### mDNS Forwarding

mDNS forwarding allows device discovery to cross VLAN boundaries. **Off by default in UniFi — only enable where explicitly needed.**

| Network | mDNS | Reason |
| ------- | ---- | ------ |
| Management (10) | Off | Proxmox/Athena don't use mDNS |
| Cluster (20) | Off | Corosync only |
| k3s (30) | **On** | Home Assistant discovers IoT devices across VLAN boundary |
| Storage (40) | Off | TrueNAS/PBS don't need it |
| Torrent (49) | Off | Airgapped |
| IoT (50) | **On** | HA ↔ IoT device discovery |
| Guest (69) | Off | Guests must not discover internal or IoT devices |
| VPN (80) | Off | Tailscale handles its own discovery |
| WireGuard (81) | Off | VPN clients don't need local discovery |
| Provisioning (99) | Off | Temporary network |

> [!NOTE]
> When adding a new network in UniFi, mDNS forwarding defaults to **off**. Only enable it on the specific pair of networks that need cross-VLAN discovery. Leaving it on unnecessarily widens your attack surface — a compromised guest device could discover and probe IoT devices.

---

### Per-VLAN Notes

###### VLAN 10 — Management
The admin plane. Reaches everything. Nothing initiates into it (firewall enforces this).
Core services that live here: Unifi controller, Proxmox web UI, Docker host, Ansible (Athena), Bind9.

**DHCP Guarding:** Enable on Management VLAN — a rogue DHCP server here could redirect all management traffic.
Settings → Networks → Management → Advanced → DHCP Guarding → Enabled.
Trusted DHCP server: `10.10.10.254` (the UXG Max gateway — the only legitimate DHCP server on this network).

###### VLAN 20 — Cluster (Corosync)
Corosync is extremely sensitive to latency. If a NIC gets flooded with backup or storage traffic,
jitter can trigger a **Fencing event (hard reboot)** of a Proxmox node.

VLAN 20 exists at the Proxmox host level only — no VMs attach to it.

**NO GATEWAY** — internal routing only.

> [!NOTE] Single Corosync ring today
> Corosync currently runs a single link on this VLAN, which shares the one physical 2.5 GbE
> trunk. The ring design (virtual ring1 as an interim, dedicated NIC as the end goal) and the
> no-QDevice decision are documented in
> [2-proxmox/pve/Corosync.md](../../../2-proxmox/pve/Corosync.md). (Switch trunks allow all
> VLANs; the remaining task is host-side `vmbr1.20` interfaces.)

Settings:
- **IGMP Snooping enabled** — prevents Corosync multicast from flooding all switch ports
- **QoS:** Tag traffic on UDP 5404–5405 with DSCP 46 (Expedited Forwarding)

###### VLAN 30 — k3s
Nodes pull from internet, access storage, talk to each other. Cannot initiate to Management.
See firewall rules for specifics.

> [!NOTE]
> k3s node IPs are set statically via cloud-init at Terraform provision time — the VM comes up with the correct IP on first boot and never touches DHCP. No need to boot → grab MAC → set reservation → reboot. MetalLB manages its own IP pool (.60–.99) entirely inside Kubernetes and is independent of UniFi DHCP.

###### VLAN 40 — Storage
East-west storage traffic only: PBS ↔ TrueNAS replication/NFS, Longhorn replica sync between worker nodes. MTU 9000 benefits these VM-to-VM flows directly.

**No gateway — internal only.** All devices are dual-homed; internet access goes via the VLAN 10 management interface.

**Proxmox → PBS backup jobs do NOT use this VLAN.** The Proxmox hypervisor hosts only have VLAN 10 IPs, so backup jobs always go over management at MTU 1500. This is acceptable — PBS compresses and deduplicates before sending, so actual wire traffic is much smaller than raw VM size.

MTU 9000 (Jumbo Frames) — must be configured end-to-end on every device on this VLAN. See [Switching.md](Switching.md#jumbo-frames).

###### VLAN 49 — Torrent
Fully airgapped from the internal network. WAN access only.
gluetun (VPN killswitch), qBittorrent, Soularr live here.

> RFC1918 block required in firewall. UniFi doesn't have a built-in RFC1918 alias —
> create an IP group covering `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`.

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

###### VLAN 69 — Guest
AP guest WiFi. Internet access only — isolated from all internal VLANs and from other
guest clients (client isolation on). UniFi manages DHCP automatically.

###### VLAN 80 — Tailscale
Tailscale subnet router only. VPN users get scoped access to Management, k3s, and Storage.
Zone: `Tailscale`. See firewall rules for exact permissions.

###### VLAN 81 — Wireguard
UniFi WireGuard VPN server. Fallback remote access for devices that can't run Tailscale.
Zone: `Wireguard`. Requires public IP or DDNS. See [VPN.md](VPN.md) for setup.

###### VLAN 99 — Provisioning
> [!NOTE] Unused — netboot abandoned
> This VLAN existed for PXE provisioning. Nodes now install via
> [Ventoy USB](../../../2-proxmox/provisioning/Ventoy.md) directly onto Management (VLAN 10),
> so VLAN 99, its DHCP boot options, and the dedicated provisioning port are no longer
> needed. See the [post-mortem](../../Alternative%20Methods/Netboot/README.md). Kept here until the VLAN and the
> Libre Potato are formally decommissioned/repurposed.

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

> The full host/VM/VIP list with IPs, node placement, and roles is the authoritative
> inventory: **[MAC Reservations.md](../Assignments/MAC%20Reservations.md)**. VM resource
> sizing (vCPU/RAM/disk) is in the Terraform spec:
> [provisioning/README.md](../../../2-proxmox/provisioning/README.md#vm-spec-table).
> Not duplicated here to avoid drift.

> [!NOTE] Athena — Why everything lives here
> Athena is the management plane. Gitea and Semaphore live here rather than
> on the Docker host to avoid a bootstrap chicken-and-egg problem — Traefik
> (on Docker) can't be up before Semaphore, but Semaphore is needed to bring
> Traefik up. Athena is reachable by IP directly during bootstrap, then gets
> a subdomain via Traefik later once it's running.
>
> Gitea is configured with GitHub push mirroring — every push to Gitea
> automatically mirrors to GitHub as an offsite backup.

