# Networks

| Name | VLAN ID | CIDR | Gateway | Notes |
| --- | --- | --- | --- | --- |
| Management | 10 | 10.10.10.0/24 | 10.10.10.254 | SSH, Web UI, UniFi, Bind9. PXE boot enabled. |
| Cluster | 20 | 10.10.20.0/24 | None | Corosync only. QoS DSCP 46. DHCP disabled. |
| k3s | 30 | 10.10.30.0/24 | 10.10.30.254 | Workloads, MetalLB, Longhorn. DHCP pool starts at .200. |
| Storage | 40 | 10.10.40.0/24 | 10.10.40.254 | Jumbo Frames (MTU 9000). Outbound updates only. DHCP disabled. |
| IoT | 50 | 10.10.50.0/24 | 10.10.50.254 | Smart home devices. Isolated — only Home Assistant can initiate in. |
| Torrent | 49 | 172.16.20.0/24 | 172.16.20.254 | Airgapped from all RFC1918. WAN only. |
| Tailscale VPN | 80 | 10.10.80.0/24 | 10.10.80.254 | Tailscale subnet router. |
| WireGuard VPN | 81 | 10.10.81.0/24 | 10.10.81.254 | UniFi WireGuard server. Remote access fallback for devices that can't run Tailscale. |
| Guest | — | 172.69.69.0/24 | 172.69.69.254 | AP guest WiFi. Client isolation. Internet only. |
| Provisioning | 99 | 10.10.99.0/24 | 10.10.99.254 | PXE boot only. Short lease. |

See [VLANs + VMs.md](VLANs%20+%20VMs.md) for full DHCP ranges, mDNS settings, and per-VLAN notes.

---

## DNS Per-Network

Configure DNS per-network (not at gateway level) for full control:
Settings → Networks → [Network] → Advanced → DHCP Name Server → uncheck Auto.

| Network | DNS servers | Reason |
| --- | --- | --- |
| Management | `10.10.10.8` (Bind9/Athena), `9.9.9.9` fallback | Full internal resolution |
| k3s | `10.10.10.8`, `9.9.9.9` fallback | Internal resolution for workloads |
| Storage | `10.10.10.8`, `9.9.9.9` fallback | Internal resolution |
| Tailscale VPN | `10.10.10.8`, `9.9.9.9` fallback | Same as management |
| WireGuard VPN | `10.10.10.8`, `9.9.9.9` fallback | Remote clients need internal resolution |
| Provisioning | `10.10.10.8`, `9.9.9.9` fallback | PXE nodes need internal DNS |
| Torrent | `9.9.9.9` only | Internal IPs would break the airgap |
| IoT | Gateway default (UniFi content filter) | Do not point at Bind9 — see below |
| Guest | Gateway default (UniFi content filter) | Do not point at Bind9 — see below |

### Two-Phase Setup

- **Bootstrap (before Bind9 is live):** allow all VLANs `→ WAN` port 53, use `9.9.9.9 / 1.1.1.1` as temporary resolvers
- **Post-Bind9:** change destination to Athena (`10.10.10.8`) for all trusted VLANs — forces nodes through the internal resolver and prevents bypassing it via arbitrary internet DNS

### Upstream Resolver: Quad9 DoH — IPv4 Filtered (primary)

Bind9 on Athena forwards upstream to Quad9's filtered DoH endpoint, which blocks malicious domains at the resolver before any firewall rule fires:

- DoH URL: `https://dns.quad9.net/dns-query`
- Plain IPv4 (fallback / bootstrap): `9.9.9.9`
- Port for DoT: `853`
- Configure in Bind9 as a DoT forwarder (`9.9.9.9` port 853) or DoH via a stub resolver (e.g. `dns-over-https` package or Unbound as a front-end)

### Guest and IoT — UniFi Built-in Content Filter (not Bind9)

Guest WiFi and IoT must **not** point at the internal Bind9/AdGuard instance — that exposes your internal resolver to untrusted devices.

Use UniFi's per-network content filter instead:
- Network → [Guest or IoT] → Advanced → Content Filtering → enable **Ad Blocking**
- Runs at the gateway with no internal infrastructure exposed
- Filtering quality is lower than AdGuard (no custom rules), but sufficient for ad/tracker blocking on untrusted networks

| Network | DNS resolver | Content filter |
| --- | --- | --- |
| Management, k3s, Storage, Tailscale VPN, WireGuard VPN, Provisioning | Bind9 → Quad9 DoH | AdGuard (via Bind9) |
| IoT | Gateway default | UniFi Ad Blocking |
| Guest | Gateway default | UniFi Ad Blocking |
| Torrent | `9.9.9.9` direct | None |

---

## mDNS Proxy

Settings → Networks → [Network] → Advanced → mDNS

Bridges multicast DNS announcements between VLANs so Home Assistant (k3s VLAN 30 or Docker on VLAN 10) can discover smart home devices (IoT VLAN 50).

**Current config:**
- VLANs in proxy: **Management (10)**, **k3s (30)**, **IoT (50)**
- Scope to specific device types (Chromecast, Apple TV, Sonos) — prevents all k3s services from being announced into IoT

> [!NOTE]
> If UniFi's mDNS forwarder proves unreliable (devices disappear after a few hours), deploy an Avahi container bridged across both VLANs. It's more reliable than the built-in forwarder for complex mDNS setups.

---

## IGMP Snooping

Settings → Switching → IGMP Snooping (or per-network Advanced settings)

**Enable per-VLAN.** Prevents multicast traffic from flooding every switch port — only forwards to ports that have requested membership.

Without it: Chromecast, Apple TV, Sonos, and other multicast-heavy devices send traffic to every port on the VLAN.

Enable on: **IoT (50)**, **k3s (30)**, **Management (10)**. Not needed on Cluster (20, no gateway) or Torrent (49, no multicast).

---

## Jumbo Frames (MTU 9000)

Enable on **specific switch ports only** — not globally.

Ports that need jumbo frames: switch ports connected to storage nodes (pve-srv-1 on USW Flex Mini port 1, TrueNAS if directly connected).

**Do not enable globally.** Devices that can't handle 9000 MTU will silently drop oversized packets. Storage nodes are the only ones that benefit.

See [Switch_Port_Assignments.md](Switch_Port_Assignments.md) for port layout.

---

## QoS

Settings → Traffic Management → QoS

Prevents Torrent traffic from saturating the WAN uplink and degrading SSH and video calls.

| VLAN | Priority | Reason |
| --- | --- | --- |
| Management (10) | Highest | Admin SSH must never lag |
| Tailscale VPN (80) / WireGuard VPN (81) | High | Remote access |
| k3s (30) | Medium | Workload traffic |
| IoT (50) | Medium-low | Smart home, not latency-sensitive |
| Torrent (49) | Lowest | Bulk transfer, should never starve others |

**Also enable Smart Queue Management (SQM)** on the WAN interface — prevents bufferbloat, which makes the connection feel laggy during heavy downloads even when raw throughput is fine. More impactful than queue priorities for most homelab usage.
