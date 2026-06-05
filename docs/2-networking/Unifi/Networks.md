# Networks

| Name | VLAN ID | CIDR | Gateway | Notes |
| --- | --- | --- | --- | --- |
| Management | 10 | 10.10.10.0/24 | 10.10.10.254 | SSH, Web UI, UniFi, Bind9. PXE boot enabled. |
| Cluster | 20 | 10.10.20.0/24 | None | Corosync only. QoS DSCP 46. DHCP disabled. |
| k3s | 30 | 10.10.30.0/24 | 10.10.30.254 | Workloads, MetalLB, Longhorn. DHCP pool starts at .200. |
| Storage | 40 | 10.10.40.0/24 | 10.10.40.254 | Jumbo Frames (MTU 9000). Outbound updates only. DHCP disabled. |
| IoT | 50 | 10.10.50.0/24 | 10.10.50.254 | Smart home devices. Isolated — only Home Assistant can initiate in. |
| Torrent | 49 | 172.16.20.0/24 | 172.16.20.254 | Airgapped from all RFC1918. WAN only. |
| VPN | 80 | 10.10.80.0/24 | 10.10.80.254 | Tailscale subnet router. |
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
| VPN | `10.10.10.8`, `9.9.9.9` fallback | Same as management |
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
| Management, k3s, Storage, VPN, Provisioning | Bind9 → Quad9 DoH | AdGuard (via Bind9) |
| IoT | Gateway default | UniFi Ad Blocking |
| Guest | Gateway default | UniFi Ad Blocking |
| Torrent | `9.9.9.9` direct | None |
