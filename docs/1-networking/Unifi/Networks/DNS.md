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
| Provisioning  | `9.9.9.9`<br>`1.1.1.2`                     | PXE nodes need internet DNS                                                                   |
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
Settings → CyberSecure → Content Filter → Create filters for all networks you want it on (guest, iot) → Adblock Enabled

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
