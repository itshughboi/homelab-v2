
| Name          | VLAN ID | CIDR           | Gateway       | Notes                                                                                |
| ------------- | ------- | -------------- | ------------- | ------------------------------------------------------------------------------------ |
| Management    | 10      | 10.10.10.0/24  | 10.10.10.254  | SSH, Web, UniFi, Bind9. PXE                                                          |
| Cluster       | 20      | 10.10.20.0/24  | None          | Corosync only. QoS DSCP 46. DHCP disabled.                                           |
| k3s           | 30      | 10.10.30.0/24  | 10.10.30.254  | Workloads, MetalLB, Longhorn. DHCP pool starts at .200.                              |
| Storage       | 40      | 10.10.40.0/24  | 10.10.40.254  | Jumbo Frames (MTU 9000). Outbound updates only. DHCP disabled.                       |
| IoT           | 50      | 10.10.50.0/24  | 10.10.50.254  | Smart home devices. Isolated — only Home Assistant can initiate in.                  |
| Torrent       | 49      | 172.16.20.0/24 | 172.16.20.254 | Airgapped from all RFC1918. WAN only.                                                |
| Tailscale VPN | 80      | 10.10.80.0/24  | 10.10.80.254  | Tailscale subnet router.                                                             |
| WireGuard VPN | 81      | 10.10.81.0/24  | 10.10.81.254  | UniFi WireGuard server. Remote access fallback for devices that can't run Tailscale. |
| Guest         | —       | 172.69.69.0/24 | 172.69.69.254 | AP guest WiFi. Client isolation. Internet only.                                      |
| Provisioning  | 99      | 10.10.99.0/24  | 10.10.99.254  | PXE boot only. Short lease.                                                          |

See [VLANs + VMs.md](VLANs%20+%20VMs.md) for full DHCP ranges, mDNS settings, and per-VLAN notes.

---

## DNS Per-Network

Configure DNS per-network (not at gateway level) for full control:
Settings → Networks → [Network] → Advanced → DHCP Name Server → uncheck Auto.

| Network       | DNS servers                                | Reason                                                                                        |
| ------------- | ------------------------------------------ | --------------------------------------------------------------------------------------------- |
| Management    | `10.10.10.8`<br>`10.10.10.10`<br>`9.9.9.9` | Full internal resolution                                                                      |
| k3s           | `10.10.10.8`<br>`10.10.10.10`<br>`9.9.9.9` | Internal resolution for workloads                                                             |
| Storage       | `9.9.9.9`, `1.1.1.2`                       | Package updates only. **DHCP disabled — configure statically on each machine (TrueNAS, PBS)** |
| Tailscale VPN | `10.10.10.8`<br>`10.10.10.10`<br>`9.9.9.9` | Same as management                                                                            |
| WireGuard VPN | `10.10.10.8`<br>`10.10.10.10`<br>`9.9.9.9` | Remote clients need internal resolution                                                       |
| Provisioning  | `9.9.9.9`<br>`1.1.1.2`                     | PXE nodes need internal DNS                                                                   |
| Torrent       | `9.9.9.9`, `1.1.1.2`                       | Internal IPs would break the airgap                                                           |
| IoT           | `9.9.9.9`, `1.1.1.2`                       |                                                                                               |
| Guest         | `9.9.9.9`, `1.1.1.2`                       |                                                                                               |

### DNS Resolution Chain

- Bind9 (`10.10.10.8`) is authoritative for `*.hughboi.cc` and `*.hughboi.vip` — answers these directly from zone files
- All other queries are forwarded to AdGuard (`10.10.10.10`), which handles ad/tracker blocking
- AdGuard passes unblocked queries to Unbound, which does full recursion via Quad9
- If AdGuard is unreachable, Bind9 falls back to `9.9.9.9` (Quad9) directly

### UniFi Content Filter

Guest WiFi and IoT must **not** point at the internal Bind9/AdGuard instance — that exposes your internal resolver to untrusted devices.

Use UniFi's content filter instead:
- Settings -> CyberSecure -> Content Filter -> Create filters for all networks you want it on (guest, iot) -> Adblock Enabled



---

## mDNS Proxy

Settings → Networks → [Network] → Advanced → mDNS

Bridges multicast DNS announcements between VLANs so Home Assistant (k3s VLAN 30 or Docker on VLAN 10) can discover smart home devices (IoT VLAN 50).

**Current config:**
- VLANs in proxy: 
	- Management (10)
	- k3s (30)
	- IoT (50)
- Scope to specific device types (Chromecast, Apple TV, Sonos) — prevents all k3s services from being announced into IoT

> [!NOTE]
> If UniFi's mDNS forwarder proves unreliable (devices disappear after a few hours), deploy an Avahi container bridged across both VLANs. It's more reliable than the built-in forwarder for complex mDNS setups.

---

## IGMP Snooping

Settings → Switching → IGMP Snooping (or per-network Advanced settings)

**Enable per-VLAN.** Prevents multicast traffic from flooding every switch port — only forwards to ports that have requested membership.

Without it: Chromecast, Apple TV, Sonos, and other multicast-heavy devices send traffic to every port on the VLAN.

Enable on: 
- Management (10)
- k3s (30)
- IoT (50)

---

## Jumbo Frames (MTU 9000)

Jumbo frames are enabled globally on the switch, but only take effect on VLANs where MTU 9000 is configured. Devices on other VLANs are unaffected.

MTU 9000 fits ~6x more data per packet than standard MTU 1500 — fewer packets means less per-packet overhead (headers, interrupts, CPU cycles), which directly increases NFS/backup throughput between Proxmox, TrueNAS, and PBS.

- **Enable on switch:** Devices → [USW Flex Mini] → Settings → Disable Global Switch Settings → Jumbo Frames Enabled
- **Set per-network:** Settings → Networks → Storage (VLAN 40) → MTU → 9000

**Verify end-to-end after any infrastructure change** — partial MTU support causes silent packet loss with no errors, just degraded throughput. Only testable once TrueNAS or PBS has a `10.10.40.x` IP.

```sh
# Run from a storage node targeting TrueNAS (or between any two VLAN 40 hosts)
# -M do = prohibit fragmentation  
# -s 8972 = 9000 MTU minus 28-byte IP+ICMP headers
ping -M do -s 8972 10.10.40.x

# If it fails, step down to find the ceiling:
ping -M do -s 4000 10.10.40.x
ping -M do -s 1472 10.10.40.x   # standard 1500 MTU ceiling — if this fails, MTU is broken everywhere
```

MTU 9000 checklist — every item must be set, partial is broken:
- [ ] UniFi switch: Devices → [USW Flex Mini] → Settings → Disable Global Switch Settings → Jumbo Frames Enabled
- [ ] UniFi network: Settings → Networks → Storage (VLAN 40) → MTU → 9000
- [ ] Proxmox slave port (e.g. enp42s0 for pve-srv-1)
- [ ] Proxmox parent bridge (`vmbr1` on pve-srv-1, `vmbr0` on pve-srv-2/3/4) → MTU 9000
	- [ ] See [[Virtual Interfaces]]
- [ ] Proxmox VLAN sub-interface (`.40`) → MTU 9000
- [ ] TrueNAS NIC on VLAN 40 → MTU 9000
- [ ] PBS NIC on VLAN 40 → MTU 9000

---

## QoS

> [!IMPORTANT] **Prerequisite — enable Smart Queue Management (SQM) first**
> QoS policies cannot be saved until SQM is active on the WAN interface.
> Settings → Internet → [WAN] → Advanced → Manual → Smart Queues → enable → set Downrate and Uprate to your actual ISP speeds → Save.
> SQM also prevents bufferbloat independently of QoS policies — it's worth enabling regardless.

Settings → Overview → Policy Based Routing → Create Policy

| VLAN                                    | Priority   | Behavior             | Reason                                         |
| --------------------------------------- | ---------- | -------------------- | ---------------------------------------------- |
| Management (10)                         | Highest    | Prioritize           | Admin SSH must never lag                       |
| Tailscale VPN (80) / WireGuard VPN (81) | High       | Prioritize           | Remote access                                  |
| k3s (30)                                | Medium     | Prioritize           | Workload traffic                               |
| IoT (50)                                | Medium-low | Prioritize           | Smart home, not latency-sensitive              |
| Torrent (49)                            | Lowest     | Prioritize and Limit | Cap upload so it can't starve everything else. |

**Prioritize** — marks traffic for priority queuing, no bandwidth cap. Use for anything you want to go fast.
**Prioritize and Limit** — caps bandwidth AND marks as lowest priority. Use for Torrent — set the upload limit to something like `15 Mbps` (leaving ~5 Mbps headroom on a 20 Mbps uplink) so it physically cannot consume the full pipe.

**Torrent**: Set Upload Burst: "Short" in QoS policy