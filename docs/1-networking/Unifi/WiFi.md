# WiFi Settings

---

## Channel AI

Settings → WiFi → Radio Manager → Channel AI

**Enable it.** Automatically selects optimal channels and adjusts TX power based on RF environment. Reduces interference and eliminates manual channel tuning. Runs periodically in the background — changes are applied during low-traffic windows.

---

## WiFiman Support

Settings → System → WiFiman

**Enable it.** Allows the WiFiman app (iOS/Android) to discover this network for:
- WAN speed tests from the gateway
- Ping and traceroute tests
- WiFi signal analysis and channel scanning

Zero overhead. No reason to leave it off.

---

## Guest Network — Speed Limit

Settings → WiFi → [Guest SSID] → Advanced → Client Rate Limiting

**Enable per-client rate limiting.** Without it a single guest can saturate your WAN uplink.

| Direction | Recommended limit |
| --- | --- |
| Download | 50 Mbps |
| Upload | 25 Mbps |

Adjust based on your WAN speed. The goal is preventing a single guest from hogging the pipe, not degrading normal browsing.

Guest SSID is bound to VLAN — see [Networks.md](Networks.md). Client isolation is enabled; guests cannot see each other or any internal hosts.

---

## mDNS Proxy

Settings → Networks → [VLAN] → Advanced → mDNS

The mDNS proxy bridges multicast DNS announcements between VLANs so Home Assistant (on k3s VLAN 30) can discover smart home devices (on IoT VLAN 50).

**Current config:**
- VLANs in proxy: **k3s (30)** and **IoT (50)**
- Service scope: scoped to specific device types you want discoverable (Chromecast, Apple TV, Sonos, etc.)

This is the correct approach — scoping by service/device type prevents all k3s services from being announced into IoT. Any wireless device you want HA to discover needs to be in the service scope list.

> [!NOTE]
> If UniFi's mDNS forwarder proves unreliable (devices disappear after a few hours),
> deploy an Avahi container on Athena bridged across both VLANs as a dedicated reflector.
> It's more reliable than the built-in forwarder for complex mDNS setups.

---

## QoS

Settings → Traffic Management → QoS

For this setup the highest-value change is preventing Torrent traffic from saturating the WAN uplink and degrading SSH and video calls.

**Recommended queue priorities:**

| VLAN | Priority | Reason |
| --- | --- | --- |
| Management (10) | Highest | Admin SSH must never lag |
| VPN (80) | High | Remote access |
| k3s (30) | Medium | Workload traffic |
| IoT (50) | Medium-low | Smart home, not latency-sensitive |
| Torrent (49) | Lowest | Bulk transfer, should never starve others |

**Also enable Smart Queue Management (SQM)** on the WAN interface — it prevents bufferbloat, which makes the connection feel laggy during heavy downloads even when raw throughput is fine. SQM is more impactful than queue priorities for most homelab usage.

---

## WireGuard VPN Server (Future — requires public IP)

Settings → VPN → WireGuard Server

Not set up yet — requires a static public IP or a DDNS entry pointing at your WAN.

When ready:
1. Settings → VPN → VPN Server → Create → WireGuard
2. Set listen port: UDP **51820** (or custom)
3. Assign a VPN subnet (separate from Tailscale — don't overlap with 10.10.80.0/24)
4. Generate client config from the UI — download the QR code or `.conf` file
5. Create a firewall allow for WAN → VPN UDP 51820

> [!NOTE]
> You already have Tailscale on VLAN 80. WireGuard via UniFi would be a second VPN path
> (useful as a backup or for devices that can't run Tailscale). Keep subnets distinct.

---

## IGMP Snooping

Settings → Switching → IGMP Snooping (or per-network)

**Enable per-VLAN, especially IoT.** IGMP snooping prevents multicast traffic from flooding every switch port — instead it only forwards multicast to ports that have requested membership.

Without it: Chromecast, Apple TV, Sonos, and other multicast-heavy devices send traffic to every port on the VLAN, increasing load on all devices including ones that don't care about that traffic.

Enable on: **IoT (50)**, **k3s (30)**, **Management (10)**. Not needed on Cluster (20, no gateway) or Torrent (49, no multicast).

---

## Jumbo Frames

Enable jumbo frames (MTU 9000) **on specific switch ports only** — not globally.

Ports that need jumbo frames: switch ports connected to storage nodes (pve-srv-1 on USW Flex Mini port 1, TrueNAS node if directly connected).

**Do not enable globally.** Devices that don't handle 9000 MTU correctly will silently drop oversized packets, causing hard-to-debug connectivity issues. Storage nodes are the only ones that benefit.

See [Switch_Port_Assignments.md](Switch_Port_Assignments.md) for port layout.
