# VPN

Two VPN paths are available. They serve different purposes and must not share subnets.

| VPN | VLAN | Subnet | Purpose |
| --- | --- | --- | --- |
| Tailscale | 80 | 10.10.80.0/24 | Primary remote access. Agent-based, works behind CGNAT, no port forwarding needed. |
| WireGuard (UniFi) | 81 | 10.10.81.0/24 | Fallback for devices that can't run Tailscale. Requires public IP or DDNS. |

Subnets must stay distinct — both create routes and overlapping them causes routing conflicts.

---

## Tailscale (VLAN 80)

Tailscale runs as a subnet router on a dedicated VM in VLAN 80, advertising internal RFC1918 routes to remote devices. No port forwarding required — Tailscale punches through NAT via its coordination server.

VLAN 80 is pre-configured here so the network exists when the Tailscale VM is provisioned later. The VM itself, Tailscale installation, and route advertisement are set up after Proxmox is running — see `docs/5-security/Tailscale.md`.

---

## WireGuard VPN Server (VLAN 81 — requires public IP or DDNS)

Settings → VPN → VPN Server → Create → WireGuard

1. Set listen port: **UDP 51820**
2. Set VPN subnet: **10.10.81.0/24**
3. Generate client configs from the UI — download QR code or `.conf` file
4. Add firewall rule: `WAN → WireGuard UDP 51820` (allows inbound tunnel establishment)

Client devices connect and receive an IP from `10.10.81.0/24`. They resolve internal hostnames via Bind9 (`10.10.10.8`) — set in [Networks/DNS.md](Networks/DNS.md).

> [!NOTE]
> The `WAN → UDP 51820` firewall rule is required. Without it the UXG Max blocks all inbound connections on that port and no client can establish the tunnel.
