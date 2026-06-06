
Per-VLAN rule tables. For zone names and port group definitions see [Reference.md](Reference.md).
For setup procedure and behavioral notes see [README.md](README.md).

---

## Global Rule Order

> [!DANGER]
> **This order must be enforced in UniFi.** Rules fire top-to-bottom; a DENY above
> an ALLOW silently wins. After any restore or rule change, verify this sequence.

| Global Priority | Rule | Why it must be here |
| --- | --- | --- |
| **1** | `ANY → ANY` state `established/related` ALLOW | Return traffic for all initiated connections. Missing this = all responses dropped. |
| **2** | `MGMT → MGMT ANY` ALLOW | Intra-VLAN admin traffic. Zone firewall intercepts same-subnet traffic — without this your Mac can't reach pve-srv nodes or the controller VM. **Root cause of June 2026 lockout.** |
| **3** | `VPN → MGMT SSH,WEB` ALLOW | Remote admin via Tailscale. Must be above the MGMT deny below. |
| **4–N** | All other ALLOW rules | Per-VLAN sections below. |
| **last** | `ANY → MGMT DENY` | Default deny inbound to admin plane. Must come after all explicit ALLOWs above. |

---

## Management (10.10.10.0/24)

*Admin plane. Reaches everything. Nothing initiates into it.*

| Priority | Source              | Destination                  | Services  | Intent                                           |
| -------- | ------------------- | ---------------------------- | --------- | ------------------------------------------------ |
| 1        | MGMT                | MGMT (10.10.10.0/24)         | ANY       | Intra-VLAN admin traffic — prevents self-lockout |
| 2        | MGMT                | K3S (10.10.30.0/24)          | SSH, K3S  | Admin control                                    |
| 3        | MGMT                | STORAGE (10.10.40.0/24)      | SSH, WEB  | Admin access to TrueNAS + PBS web UIs only       |
| 4        | MGMT                | TORRENT (172.16.20.0/24)     | SSH       | Admin access only                                |
| 5        | MGMT                | VPN (10.10.80.0/24)          | SSH       | Admin access                                     |
| 6        | MGMT                | PROVISIONING (10.10.99.0/24) | SSH       | PXE control                                      |
| 7        | MGMT                | WAN                          | CORE, WEB | Updates, DNS, NTP                                |
| 8        | VPN (10.10.80.0/24) | MGMT                         | SSH, WEB  | Remote admin                                     |
| last     | ANY                 | MGMT                         | DENY      | No inbound initiation from other zones           |



> [!NOTE]
> The UXG Max gateway (10.10.10.254) must reach the controller VM (10.10.10.10) on
> ports 8080 and 8443. This is covered by `MGMT → MGMT ANY` above — do not remove it.

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
| K3S | K3S | ANY | Intra-VLAN — pod networking and node-to-node traffic |
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
> Longhorn replica sync uses ports 9500–9504 between k3s nodes. Covered by `K3S → K3S ANY` above.

---

## Storage (10.10.40.0/24)

*Has gateway for outbound updates only. Jumbo frames (MTU 9000). Accepts connections from Management and k3s only.*

| Source | Destination | Services | Intent |
| --- | --- | --- | --- |
| STORAGE | STORAGE | ANY | Intra-VLAN — PBS → TrueNAS backups |
| MGMT | STORAGE | SSH, WEB | Admin access to TrueNAS + PBS web UIs |
| K3S | STORAGE | NFS 2049, rpcbind 111, iSCSI 3260, node_exporter 9100, Longhorn 9500 | Volume access + Prometheus scraping |
| STORAGE | WAN | CORE, WEB | Updates only |
| ANY | STORAGE | DENY | Default deny inbound |

> [!DANGER] MTU must be 9000 end-to-end — switch ports, NICs, Proxmox bridges, and VMs. Partial MTU causes silent packet loss.

---

## IoT (10.10.50.0/24)

*Smart home devices. Untrusted — cannot initiate to any internal network. Home Assistant is the sole exception, reaching in from k3s.*

| Source | Destination | Services | Intent |
| --- | --- | --- | --- |
| MGMT | IoT | SSH, WEB | Admin access to device UIs |
| K3S (entire zone for now) | IoT | any | Home Assistant device control |
| IoT | WAN | CORE, WEB | Device updates and cloud APIs |
| IoT | RFC1918 | **DENY** | No internal access |
| ANY | IoT | **DENY** | No inbound access |

> [!WARNING] **TODO — tighten K3S → IoT source once Home Assistant is deployed**
> Current rule allows the entire k3s zone (10.10.30.0/24) into IoT. Once HA is running,
> scope the source to its specific LoadBalancer IP assigned by MetalLB.
> HA will run on Docker (dock-prod), not k3s — update this rule source to the dock-prod IP
> (`10.10.10.10`) and move the rule to MGMT → IoT instead of K3S → IoT.

---

## Torrent (172.16.20.0/24)

*Fully airgapped from internal network. WAN only.*

| Source | Destination | Services | Intent |
| --- | --- | --- | --- |
| MGMT | TORRENT | SSH | Admin access |
| TORRENT VM IP (172.16.20.x) | TrueNAS IP (10.10.40.x) | NFS 2049 | Download writes to TrueNAS — scoped to exact IPs, not whole zones |
| TORRENT | WAN | CORE, WEB, TORRENT | Internet + torrent traffic |
| TORRENT | RFC1918 | DENY | Full internal isolation |
| ANY | TORRENT | DENY | No inbound access |

> [!IMPORTANT]
> The `TORRENT → TrueNAS NFS` rule must be locked to the specific torrent VM IP as source
> and the specific TrueNAS IP as destination — not zone-to-zone. Fill in the exact IPs from
> your MAC reservations. Also scope the NFS export on TrueNAS to the downloads dataset only
> (not the whole pool) — a compromised torrent client can then only touch downloads.

> [!WARNING] **TODO — TrueNAS is not yet on VLAN 40**
> TrueNAS is currently on Management (10.10.10.5) while the VLAN 40 migration is pending.
> The `TORRENT → TrueNAS NFS` rule in UniFi currently points at `10.10.10.5`, not `10.10.40.x`.
> When TrueNAS moves to VLAN 40:
> 1. Update the rule destination from `10.10.10.5` → new `10.10.40.x` IP
> 2. Confirm the MGMT → STORAGE rule still covers the TrueNAS web UI on the new IP
> 3. Update MAC reservation in UniFi to reflect the new network assignment

> [!NOTE]
> RFC1918 is not a built-in alias in UniFi. Create an IP group covering
> `10.0.0.0/8`, `172.16.0.0/12`, and `192.168.0.0/16` and reference it in
> the `TORRENT → RFC1918 DENY` rule.

---

## VPN — Tailscale (10.10.80.0/24)

*Tailscale subnet router. VPN users get scoped access to Management, k3s, and Storage.*

| Source | Destination | Services | Intent |
| --- | --- | --- | --- |
| VPN | MGMT | SSH, WEB | Admin access — ensure this is above ANY→MGMT DENY |
| VPN | K3S | K3S | Cluster access |
| VPN | STORAGE | SSH, WEB | Remote admin access |
| VPN | WAN | VPN | Tunnel egress |
| ANY | VPN | DENY | No inbound access |

> [!NOTE]
> Two `VPN → MGMT` allow rules will exist in UniFi — one from the `Tailscale` zone (this section)
> and one from the `Wireguard` zone (see WireGuard section below). These are not duplicates — they cover different tunnels. Keep both.

> [!TIP]
> **Owner access is intentionally broad** — full reach to MGMT, k3s, and Storage via Tailscale is correct for solo use.
>
> **Before sharing Tailscale access with anyone else**, restrict them via Tailscale ACLs in the admin console (tailscale.com/admin/acls):
> - Tag the shared device (e.g. `tag:limited`)
> - Write a grant that allows only specific subnets or IPs (e.g. Grafana IP only, no MGMT)
> - Owner device keeps `*` access; tagged guests get scoped access
> Never hand out your Tailscale auth key — generate a separate reusable key per person and revoke it when done.

---

## VPN — WireGuard (10.10.81.0/24)

*UniFi native VPN server. Remote access fallback for devices that can't run Tailscale. Requires public IP or DDNS.*

> [!NOTE]
> The inbound tunnel rule destination is `Gateway` — the WireGuard server runs on the UXG Max itself, not a VM.
> The `Wireguard` zone applies to the network/clients, not the server process.

| Source | Destination | Services | Intent |
| --- | --- | --- | --- |
| **External (WAN)** | **Gateway** | **UDP 51820** | **Allow inbound tunnel establishment — required or no client can connect** |
| Wireguard | MGMT | SSH, WEB | Remote admin |
| Wireguard | K3S | K3S | Cluster access |
| Wireguard | STORAGE | SSH, WEB | Remote admin access |
| Wireguard | WAN | CORE, WEB | Internet egress for connected clients |
| ANY | Wireguard | DENY | No other inbound access |

> [!NOTE]
> WireGuard clients receive IPs from `10.10.81.0/24` and resolve internal hostnames via Bind9 (`10.10.10.8`) —
> configured in [Networks.md](../Networks.md). No additional DNS rules needed beyond what the Tailscale section already has.

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
