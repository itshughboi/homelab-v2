# Firewall Rules

> [!CAUTION]
> ALLOW rules must be ABOVE DENY rules in UniFi (rule order matters).
> Verify correct rule direction (LAN IN vs LAN OUT).

---

## First — Two Things Before Any Rules

1. **Enable "Block inter-VLAN traffic"** in UniFi Network settings. This is the baseline default-deny. ALLOW rules below punch specific holes in it.

2. Add this as the **very first rule in LAN IN**, before any VLAN-specific rules:
   `ALLOW ALL → ALL  state: established, related`
   This permits return traffic for connections you initiated, without needing explicit rules in both directions. Without it, outbound ALLOWs work but responses get dropped.

---

## Architecture

| Layer | VLAN | Trust Level | Description |
| --- | --- | --- | --- |
| Control Plane | Management (10) | Fully trusted | Admin origin, full infrastructure control |
| Compute Plane | k3s (30) | Semi-trusted | Runs workloads and applications |
| Data Plane | Storage (40) | Highly restricted | Critical data services (NFS, PBS, etc.) |
| Edge / Risk Zone | Torrent (69) | Untrusted | Internet-facing, high-risk traffic |
| Access Plane | VPN (80) | Conditionally trusted | User entry point into network |
| Lifecycle | Provisioning (99) | Zero-trust / Disposable | Temporary systems for provisioning |

---

## Service Groups (Legend)

| Group | Ports |
| --- | --- |
| SSH | 22 TCP |
| CORE | DNS 53 TCP/UDP, DHCP 67/68 UDP, NTP 123 UDP |
| WEB | HTTP 80 TCP, HTTPS 443 TCP |
| BOOT | TFTP 69 UDP, HTTP/HTTPS (PXE) |
| STORAGE | NFS 2049, rpcbind 111, SMB 445, iSCSI 3260 |
| COROSYNC | 5404–5405 UDP, 2224 TCP |
| K3S | 6443 TCP, 8472 UDP |
| MONITOR | 9100, 9090, 3000, 3100, 8086 TCP |
| TORRENT | 6881–6889 TCP/UDP |
| VPN | 41641 UDP (Tailscale) |

---

## DNS — Two-Phase Setup

All VLANs need DNS reachability, but the source changes over time:
- **Bootstrap:** allow `→ WAN` on port 53 (using 9.9.9.9 / 1.1.1.1)
- **Post-Bind9:** change destination from WAN to Athena's IP (`10.10.10.8`) for all VLANs — forces all nodes through the internal resolver and prevents bypassing it via arbitrary internet DNS

---

## Management (10.10.10.0/24)

*Admin plane. Reaches everything. Nothing initiates into it.*

| Source | Destination | Services | Intent |
| --- | --- | --- | --- |
| MGMT | K3S (10.10.30.0/24) | SSH, K3S | Admin control |
| MGMT | STORAGE (10.10.40.0/24) | SSH, WEB, STORAGE, MONITOR | Full admin + monitoring |
| MGMT | TORRENT (172.16.20.0/24) | SSH | Admin access only |
| MGMT | VPN (10.10.80.0/24) | SSH | Admin access |
| MGMT | PROVISIONING (10.10.99.0/24) | SSH | PXE control |
| MGMT | WAN | CORE, WEB | Updates, DNS, NTP |
| ANY | MGMT | DENY | No inbound initiation |

---

## Cluster (10.10.20.0/24)

*Corosync heartbeat only. No gateway. Completely isolated. Intra-VLAN traffic is invisible to the firewall — no rules needed for Corosync itself.*

| Source | Destination | Services | Intent |
| --- | --- | --- | --- |
| ANY | CLUSTER | DENY | Fully isolated |

---

## k3s (10.10.30.0/24)

*Nodes talk to each other, pull from internet, access storage. Cannot initiate to Management.*

| Source | Destination | Services | Intent |
| --- | --- | --- | --- |
| MGMT | K3S | SSH, K3S | Admin/API access |
| K3S | STORAGE | STORAGE | Persistent volumes |
| K3S | WAN | CORE, WEB | Images, DNS, NTP |
| K3S | MGMT | DENY | No lateral movement |
| ANY | K3S | DENY | Block inbound |

> [!IMPORTANT] Post-bootstrap
> Once Bind9 is live on Athena, change the `K3S → WAN CORE` rule destination
> from `WAN` to the Bind9 IP specifically. Prevents nodes from bypassing the
> internal resolver.

> [!TIP] Longhorn
> Longhorn replica sync uses ports 9500–9504 between k3s nodes. These are
> intra-VLAN so no firewall rules needed, but useful when debugging storage issues.

---

## Storage (10.10.40.0/24)

*Has gateway for outbound updates only. Jumbo frames (MTU 9000). Accepts connections from Management and k3s only.*

| Source | Destination | Services | Intent |
| --- | --- | --- | --- |
| MGMT | STORAGE | SSH, WEB, STORAGE, MONITOR | Admin + monitoring |
| K3S | STORAGE | STORAGE | Volume access |
| STORAGE | WAN | CORE, WEB | Updates only |
| ANY | STORAGE | DENY | Default deny inbound |

> [!DANGER] MTU must be 9000 end-to-end — switch ports, NICs, Proxmox bridges, and VMs. Partial MTU causes silent packet loss.

---

## Torrent (172.16.20.0/24)

*Fully airgapped from internal network. WAN only.*

| Source | Destination | Services | Intent |
| --- | --- | --- | --- |
| MGMT | TORRENT | SSH | Admin access |
| TORRENT | WAN | CORE, WEB, TORRENT | Internet + torrent traffic |
| TORRENT | RFC1918 | DENY | Full internal isolation |
| ANY | TORRENT | DENY | No inbound access |

> [!NOTE]
> RFC1918 is not a built-in alias in UniFi. Create an IP group covering
> `10.0.0.0/8`, `172.16.0.0/12`, and `192.168.0.0/16` and reference it in
> the `TORRENT → RFC1918 DENY` rule.

---

## VPN (10.10.80.0/24)

*Tailscale subnet router. VPN users get scoped access to Management, k3s, and Storage.*

| Source | Destination | Services | Intent |
| --- | --- | --- | --- |
| VPN | MGMT | SSH, WEB | Admin access |
| VPN | K3S | K3S | Cluster access |
| VPN | STORAGE | SSH, WEB | Remote admin access |
| VPN | WAN | VPN | Tunnel egress |
| ANY | VPN | DENY | No inbound access |

> [!NOTE] Tailscale static route
> For Tailscale subnet routing to work, add a static route in UniFi:
> - **Settings → Routing → Create New Route**
> - Destination: `100.64.0.0/10`
> - Type: Next Hop
> - Next Hop: Tailscale VM IP (`10.10.80.x`)
>
> Without this, the tunnel works but inter-VLAN → Tailscale peer routing fails.

> [!TIP]
> VPN users can currently reach the entire `10.10.10.0/24` mgmt subnet. Fine
> as a solo user. If VPN access is ever shared, scope the destination to specific
> IPs (Athena, Docker host) rather than the whole subnet.

---

## Provisioning (10.10.99.0/24)

*Temporary VLAN. Nodes live here only during Proxmox install, then move to Management.*

| Source | Destination | Services | Intent |
| --- | --- | --- | --- |
| MGMT | PROVISIONING | SSH | PXE control |
| PROVISIONING | WAN | CORE, WEB, BOOT | Install dependencies |
| PROVISIONING | INTERNAL | DENY | No lateral movement |
| ANY | PROVISIONING | DENY | Fully disposable |

> [!NOTE]
> PXE serving between the Libre Potato and provisioning nodes is entirely intra-VLAN.
> The firewall never sees it — no rules needed for TFTP/HTTP between netboot and booting nodes.

---

## Docker Firewall Bypass

Docker manipulates iptables directly, bypassing UniFi firewall rules for traffic already on the host.

- Never use `--network=host` on containers
- Bind Traefik to `10.10.10.10` explicitly, not `0.0.0.0`
- Use the `DOCKER-USER` iptables chain for any host-level restrictions
