
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

| Priority | Source              | Destination                  | Port group     | Intent                                           |
| -------- | ------------------- | ---------------------------- | -------------- | ------------------------------------------------ |
| 1        | MGMT                | MGMT (10.10.10.0/24)         | ANY            | Intra-VLAN admin traffic — prevents self-lockout |
| 2        | MGMT                | K3S (10.10.30.0/24)          | `k3s-api`      | Admin + API control                              |
| 3        | MGMT                | STORAGE (10.10.40.0/24)      | `admin`        | Admin access to TrueNAS + PBS web UIs            |
| 4        | MGMT                | TORRENT (172.16.20.0/24)     | `ssh`          | Admin access only (SSH, no web UIs)              |
| 5        | MGMT                | VPN (10.10.80.0/24)          | `ssh`          | Admin access to the Tailscale box                |
| 6        | MGMT                | PROVISIONING (10.10.99.0/24) | `ssh`          | **Dormant** — VLAN 99 retired but retained; rule kept ready |
| 7        | MGMT                | WAN                          | `wan-egress`   | Updates, DNS, NTP                                |
| 8        | VPN (10.10.80.0/24) | MGMT                         | `admin`        | Remote admin                                     |
| last     | ANY                 | MGMT                         | DENY           | No inbound initiation from other zones           |



> [!NOTE]
> The UXG Max gateway (10.10.10.254) must reach the controller VM (10.10.10.10) on
> ports 8080 and 8443. This is covered by `MGMT → MGMT ANY` above — do not remove it.

---

## Cluster (10.10.20.0/24)
*Corosync heartbeat only. No gateway. Completely isolated. Intra-VLAN traffic is invisible to the firewall — no rules needed for Corosync itself.*

| Source | Destination | Port group | Intent |
| --- | --- | --- | --- |
| ANY | CLUSTER | DENY | Fully isolated |

---

## k3s (10.10.30.0/24)

*Nodes talk to each other, pull from internet, access storage. Cannot initiate to Management.*

| Source | Destination | Port group | Intent |
| --- | --- | --- | --- |
| K3S | K3S | ANY | Intra-VLAN — pod networking and node-to-node traffic |
| MGMT | K3S | `k3s-api` | Admin/API access |
| K3S | STORAGE | `storage` | Persistent volumes |
| K3S | Athena Gitea (`10.10.10.8`) | `gitea` | **ArgoCD pulls IaC from Gitea** — scoped exception to the K3S→MGMT deny (must be above it) |
| K3S | DNS (`10.10.10.8`) | `dns` | Resolve `*.hughboi.cc` via Bind9 (for the Gitea hostname / images) |
| K3S | WAN | `wan-egress` | Images, DNS, NTP |
| K3S | MGMT | DENY | No lateral movement (all other MGMT) |
| ANY | K3S | DENY | Block inbound |

> [!IMPORTANT] ArgoCD ↔ Gitea (the GitOps source)
> ArgoCD runs in k3s but pulls from the **Athena** Gitea (`10.10.10.8:3000`) to avoid the
> in-cluster bootstrap cycle. Since K3S→MGMT is deny-by-default, the scoped `K3S → 10.10.10.8:3000`
> allow above is **required** or ArgoCD can't reach its source. Scope it to that IP+port only,
> not all of MGMT. (DR break-glass: if Gitea is down, ArgoCD can be pointed at the GitHub mirror.)

> [!IMPORTANT] Post-bootstrap
> Once Bind9 is live on Athena, change the `K3S → WAN CORE` rule destination
> from `WAN` to the Bind9 IP specifically. Prevents nodes from bypassing the
> internal resolver.

> [!TIP] Longhorn
> Longhorn replica sync uses ports 9500–9504 between k3s nodes. Covered by `K3S → K3S ANY` above.

---

## Storage (10.10.40.0/24)

*No gateway — internal only. Jumbo frames (MTU 9000). Accepts connections from Management and k3s only.*

| Source | Destination | Port group | Intent |
| --- | --- | --- | --- |
| STORAGE | STORAGE | ANY | Intra-VLAN — PBS → TrueNAS backups, **dock-prod → TrueNAS NFS** |
| MGMT | STORAGE | `admin` | Admin access to TrueNAS + PBS web UIs |
| K3S | STORAGE | `storage` | Volume access + Prometheus scraping (NFS, iSCSI, node_exporter, Longhorn) |
| ANY | STORAGE | DENY | Default deny inbound |

> [!NOTE] **dock-prod is dual-homed into this zone** (`10.10.40.10`)
> dock-prod's VLAN 40 leg is in the Storage zone, so its NFS to TrueNAS (`10.10.40.5`) is
> **intra-zone** — already covered by `STORAGE → STORAGE` above; no new cross-zone rule needed.
> (Unlike the torrent VM on VLAN 49, which needs the explicit exception below.) dock-prod reaches
> everything else over its VLAN 10 management leg.

> [!NOTE] No `STORAGE → WAN` rule — and that's intentional
> VLAN 40 has **no gateway configured on any storage NIC**. TrueNAS, PBS, and dock-prod are dual-homed;
> all outbound (package updates, etc.) egresses via their **VLAN 10 management interface**,
> not VLAN 40. So storage never routes out on 40 — no WAN rule is needed or wanted here.
> (UniFi may still show a gateway field for the network; it's just unused.)

> [!DANGER] MTU must be 9000 end-to-end — switch ports, NICs, Proxmox bridges, and VMs. Partial MTU causes silent packet loss.

---

## IoT (10.10.50.0/24)

*Smart home devices. Untrusted — cannot initiate to any internal network. Home Assistant is the sole exception, reaching in from k3s.*

| Source | Destination | Port group | Intent |
| --- | --- | --- | --- |
| MGMT | IoT | `admin` | Admin access to device UIs |
| K3S (entire zone for now) | IoT | ANY | Home Assistant device control |
| IoT | WAN | ANY | Device updates and cloud APIs (left open — smart-home devices hit unpredictable ports) |
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

| Source | Destination | Port group | Intent |
| --- | --- | --- | --- |
| MGMT | TORRENT | `ssh` | Admin access |
| TORRENT VM IP (172.16.20.x) | TrueNAS (`10.10.40.5`) | `nfs` | Download writes to TrueNAS — scoped to exact IPs, not whole zones |
| TORRENT | WAN | `torrent-wan` | Internet + torrent traffic |
| TORRENT | RFC1918 | DENY | Full internal isolation |
| ANY | TORRENT | DENY | No inbound access |

> [!IMPORTANT]
> The `TORRENT → TrueNAS NFS` rule must be locked to the specific torrent VM IP as source
> and the specific TrueNAS IP as destination — not zone-to-zone. Fill in the exact IPs from
> your MAC reservations. Also scope the NFS export on TrueNAS to the downloads dataset only
> (not the whole pool) — a compromised torrent client can then only touch downloads.

> [!NOTE] TrueNAS storage is on VLAN 40 (`10.10.40.5`)
> The `TORRENT → TrueNAS NFS` rule destination is the storage IP `10.10.40.5` (above). TrueNAS keeps
> its VLAN 10 management IP `10.10.10.5` for the web UI/SSH (covered by the MGMT → STORAGE rule).

> [!NOTE]
> RFC1918 is not a built-in alias in UniFi. Create an IP group covering
> `10.0.0.0/8`, `172.16.0.0/12`, and `192.168.0.0/16` and reference it in
> the `TORRENT → RFC1918 DENY` rule.

---

## Guest (172.69.69.0/24)

*AP guest WiFi. Internet-only, client isolation on, no internal access.*

| Source | Destination | Port group | Intent |
| --- | --- | --- | --- |
| GUEST | WAN | ANY | Internet only (left open — guest devices hit unpredictable ports) |
| GUEST | RFC1918 | **DENY** | No internal access |
| ANY | GUEST | **DENY** | No inbound |

> Client isolation (guest devices can't see each other) is the UniFi **Guest Network** toggle on
> the network itself, not a firewall rule. Guests resolve DNS via the gateway's encrypted DoH (no
> AdGuard) — see [DNS.md](../Networks/DNS.md). The `GUEST → WAN` allow + `ANY → GUEST DENY` are
> mostly implicit in UniFi's guest handling, but state them so the policy is explicit and auditable.

---

## VPN — Tailscale (10.10.80.0/24)

*Tailscale subnet router. VPN users get scoped access to Management, k3s, and Storage.*

| Source | Destination | Port group | Intent |
| --- | --- | --- | --- |
| VPN | MGMT | ANY | **Full remote access** (owner) — reach any port/service on management; avoids "why is this blocked" surprises. Must be above ANY→MGMT DENY |
| VPN | K3S | `k3s-api` | Cluster access |
| VPN | STORAGE | ANY | **Full** — includes NFS + SMB shares + web UIs over VPN |
| VPN | WAN | `vpn-out` | Tunnel egress (subnet router → internet; **add this — TS breaks under Block-all without it**) |
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

| Source | Destination | Port group | Intent |
| --- | --- | --- | --- |
| **External (WAN)** | **Gateway** | **`wg-in`** | **Allow inbound tunnel establishment (UDP 51820) — required or no client can connect** |
| Wireguard | MGMT | ANY | **Full remote access** (owner) — same as Tailscale |
| Wireguard | K3S | `k3s-api` | Cluster access |
| Wireguard | STORAGE | ANY | **Full** — includes NFS + SMB over VPN |
| Wireguard | WAN | `wan-egress` | Internet egress for connected clients (only if full-tunnel) |
| ANY | Wireguard | DENY | No other inbound access |

> [!NOTE]
> WireGuard clients receive IPs from `10.10.81.0/24` and resolve internal hostnames via Bind9 (`10.10.10.8`) —
> configured in [Networks/DNS.md](../Networks/DNS.md). No additional DNS rules needed beyond what the Tailscale section already has.

---

## Provisioning (10.10.99.0/24) — DORMANT (retained)

> [!NOTE] Dormant — retired but intentionally kept
> This VLAN existed for PXE/netboot provisioning, which has been **abandoned** (nodes now install
> via [Ventoy USB](../../../2-proxmox/provisioning/Ventoy.md) directly onto Management). The VLAN
> and these rules are **kept in place, dormant** — ready to re-enable if a temporary provisioning
> network is ever wanted again — **not removed**. No active ports/clients are on VLAN 99 today.
> See the [netboot post-mortem](../../Alternative%20Methods/Netboot/README.md).

*Former purpose: temporary VLAN — nodes lived here during Proxmox install, then moved to Management.*

| Source | Destination | Port group | Intent | Status |
| --- | --- | --- | --- | --- |
| MGMT | PROVISIONING | `ssh` | Admin access | Keep (dormant) |
| PROVISIONING | WAN | `wan-egress` | Install dependencies (add TFTP/BOOT only if PXE is ever revived) | Keep (dormant) |
| PROVISIONING | INTERNAL | DENY | No lateral movement | Keep (dormant) |
| ANY | PROVISIONING | DENY | Fully disposable | Keep (dormant) |

> [!NOTE]
> When PXE was active, serving between the Libre Potato and booting nodes was entirely
> intra-VLAN, so the firewall never saw it — no rules were ever needed for TFTP/HTTP. With
> Ventoy, the installer needs no network access at all (answer file is baked into the ISO),
> so no provisioning firewall rules are required going forward.

---

## Docker Firewall Bypass

Docker manipulates iptables directly, bypassing UniFi firewall rules for traffic already on the host.

- Never use `--network=host` on containers
- Bind Traefik to `10.10.10.10` explicitly, not `0.0.0.0`
- Use the `DOCKER-USER` iptables chain for any host-level restrictions
