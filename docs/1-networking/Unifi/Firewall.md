# Firewall Rules

> [!IMPORTANT]
> **Three rule systems exist in UniFi. Do not mix them.**
>
> | System | What it is | Use? |
> | --- | --- | --- |
> | **Object Oriented Networking (OON)** | Assigns Secure/Route/QoS/Schedule to devices/networks → auto-generates zone rules | Only if you commit fully to it |
> | **Zone-based firewall** | Manual zone-pair policies. What this doc describes. | **Yes — this setup uses this** |
> | **Legacy (LAN IN / LAN OUT / LAN LOCAL)** | Old per-direction rule system, being deprecated | No — never add rules here |
>
> OON sits above zones and writes auto-generated rules into the same zone rule table as your manual rules. If you have both OON objects AND manual zone rules for the same traffic, they can conflict or one can silently override the other depending on rule order.
>
> **If you have OON objects (e.g. `MGMT -> Allow ALL`, `VPN -> Allow ALL`):** check the Routing Table to see what rules they generated. If they're creating broad allow-all rules, they may be undermining specific port-level DENYs in your zone config. OON is too coarse for a multi-VLAN setup with per-port restrictions — it cannot express "MGMT → Storage only on 22, 80, 443, 8006, 8007."
>
> Confirmed zone-based: the lockout incident showed rules in MongoDB `trafficrule` collection (zone), not `firewallrule` (legacy).
> Network Lists (port/IP groups) are named objects used *within* zone rules — not a separate system.

> [!CAUTION]
> ALLOW rules must be ABOVE DENY rules in UniFi (rule order matters).

> [!WARNING]
> **Always make firewall changes from [unifi.ui.com](https://unifi.ui.com) (cloud portal), not the local controller.**
> If you create a zone or rule that blocks your own VLAN, the local controller becomes unreachable and you lock yourself out.
> The cloud portal connects independently of your local network and lets you undo the mistake.
> Learned this the hard way creating the MGMT zone.

---

## Firewall Prerequisites

1. **Enable "Block inter-VLAN traffic"** in UniFi Network settings. This is the baseline default-deny. ALLOW rules below punch specific holes in it.

2. Add this as the **very first rule in LAN IN**, before any VLAN-specific rules:
   `ALLOW ALL → ALL  state: established, related`
   This permits return traffic for connections you initiated, without needing explicit rules in both directions. Without it, outbound ALLOWs work but responses get dropped.

> See [Security.md](Security.md) for IPS, region blocking, honeypot, NetFlow, logging, and other UniFi security settings.
> See [Networks.md](Networks.md) for DNS configuration (Quad9 DoH, per-VLAN setup, Guest/IoT content filtering).

> [!TIP]
> **Rules are one direction only — always model the initiator.**
> Only create a rule for the side that *starts* the connection. The `established/related` rule above handles the response traffic automatically.
> Example: `MGMT → Torrent TCP 22` lets you SSH from MGMT into Torrent. You do not need a second rule for Torrent → MGMT. If you find yourself creating mirrored pairs, stop — the return rule is doing that work.

> [!IMPORTANT]
> **Always put the service port in Dst. Port — never Src. Port.**
> When a client initiates a connection, it connects *from* a random ephemeral port (e.g. 54832) *to* the service's well-known port (22, 80, 443) on the destination.
> A rule with `Src. Port = 22` will never match normal SSH traffic — the source port is unpredictable.
> Leave Src. Port blank (Any). Only fill in Dst. Port.
>
> **You can comma-separate multiple ports in a single rule** instead of creating one rule per port.
> Example: one rule with Dst. Port `22,80,443` replaces three separate SSH/HTTP/HTTPS rules.
> UniFi has no named port groups in the zone-based firewall UI — consolidate inline instead.

---

## Current Rule Audit (June 2026)

> [!WARNING] **`torrent to truenas` rule must be scoped down — currently Any port.**
> Torrent writes downloads to TrueNAS via NFS — the rule is intentional but far too broad.
> Change it:
> - **Dst Port:** `2049` only (NFSv4) or `111, 2049` (NFSv3 — needs rpcbind)
> - **Src:** lock to the specific torrent VM IP, not the whole Torrent zone
> - **Dst:** lock to the TrueNAS IP, not the whole Storage zone
>
> Second layer of defense (more important than the firewall rule): on TrueNAS, scope the
> NFS export to the downloads dataset only — not the entire pool. That way a compromised
> torrent client can only touch downloads, not the rest of the NAS.

> [!DANGER] **`Allow All Traffic` fires before `Block All Traffic` at the bottom.**
> The Block All Traffic system rule is effectively dead — anything not caught by an explicit Block
> above it passes through Allow All. Currently only three things are actually blocked:
> `Block IoT → Internal`, `Block Invalid Traffic`, and `Isolated Networks`.
> Everything else (including inter-VLAN paths with no explicit rule) is allowed.
> Fix: change Security Posture to **Block** in Settings → Security → Threat Management,
> which repositions the default to deny. After doing this, add explicit allows for:
> Torrent → External (internet), Provisioning → External, k3s → External, MGMT → MGMT.

> [!WARNING] **Duplicate VPN rules.**
> `Allow VPN -> All` (src zone: Internal, src: VPN/10.10.80.0/24 → dst: MGMT) and
> `Allow VPN -> MGMT` (src zone: VPN system zone → dst: MGMT) are doing the same thing
> through two different source zones. Tailscale VLAN 80 is in the Internal zone; the system
> VPN zone is for UniFi-native VPN. Remove the duplicate — keep the Internal zone version.

> [!NOTE] **VPN rules are Any port.**
> `Allow VPN -> MGMT/Storage/k3s/Provisioning` are all Dst Port: Any. Fine for solo use.
> Scope to the `admin` port group if you want tighter control.

**What's correctly configured:**
- `Allow k3s -> Storage` scoped to storage port group ✓
- `IoT -> MGMT (DNS)` scoped to dns port group ✓
- `Block IoT -> Internal` ✓
- `Storage -> MGMT (DNS)` and `k3s -> MGMT (DNS)` scoped ✓
- Return traffic handled by system `Allow Return Traffic` rule ✓
- `Isolated Networks` blocking guest ✓

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
| **4–N** | All other ALLOW rules (per-VLAN outbound) | Ordered by VLAN section below. |
| **last** | `ANY → MGMT DENY` | Default deny inbound to admin plane. Must come after all explicit ALLOWs above. |

---

## Zone Map

### System Zones (locked — UniFi-managed, cannot be removed)

| Zone | Meaning | Networks assigned |
| --- | --- | --- |
| **External** | WAN — internet-facing interfaces. This is what rules call "WAN." | Internet 1, Internet 2 |
| **Gateway** | The UXG Max device itself. Use for rules targeting the gateway (e.g. allow DNS *to* the UXG) | — (auto) |
| **VPN** | UniFi-native VPN clients only (UniFi VPN server). **Not Tailscale.** | — |
| **Hotspot** | Captive portal / guest portal networks | — |
| **DMZ** | Exposed-host zone — servers reachable from External with limited internal access | — |

> [!NOTE]
> Rules in this doc that reference "WAN" map to the **External** zone in the UniFi UI.
> Do not create a separate "WAN" zone — External already serves that purpose.

### Custom Zones

| Zone | Network / Interface | Notes |
| --- | --- | --- |
| MGMT | Management (VLAN 10) | Admin plane |
| Cluster | Cluster (VLAN 20) | Corosync only, fully isolated |
| IoT | IoT (VLAN 50) | Untrusted devices |
| Torrent | Torrent (VLAN 49) | Airgapped, WAN only |
| Internal | VPN (VLAN 80) | Tailscale subnet router |

> [!NOTE]
> The **Internal** zone currently contains VPN (Tailscale VLAN 80). Zone membership is
> not dynamic — you cannot move a network in/out of a zone per-session. Trust is
> controlled by zone policies (the rules below), not by which zone bucket the network
> sits in. If Internal has loose default policies, tighten the zone-pair rules rather
> than trying to move the network around.

> [!NOTE]
> k3s (VLAN 30), Storage (VLAN 40), and Provisioning (VLAN 99) zones not shown in the
> screenshot above — verify they are assigned to custom zones or add them.

---

## Architecture

| Layer | VLAN | Trust Level | UniFi Zone |
| --- | --- | --- | --- |
| Control Plane | Management (10) | Fully trusted | MGMT |
| Compute Plane | k3s (30) | Semi-trusted | — (verify) |
| Data Plane | Storage (40) | Highly restricted | — (verify) |
| Devices | IoT (50) | Untrusted | IoT |
| Edge / Risk Zone | Torrent (49) | Untrusted | Torrent |
| Access Plane | VPN (80) | Conditionally trusted | Internal |
| Lifecycle | Provisioning (99) | Zero-trust / Disposable | — (verify) |

---

## Service Groups (Legend)

Conceptual groups used in the rule tables below. See **UniFi Network Lists** section for the actual port groups configured in UniFi.

| Group | Ports |
| --- | --- |
| SSH | 22 TCP |
| CORE | DNS 53 TCP/UDP, DHCP 67/68 UDP, NTP 123 UDP |
| WEB | HTTP 80 TCP, HTTPS 443 TCP, Proxmox 8006 TCP, PBS 8007 TCP |
| BOOT | TFTP 69 UDP, HTTP/HTTPS (PXE) |
| STORAGE | NFS 2049, rpcbind 111, SMB 445, iSCSI 3260 |
| COROSYNC | 5404–5405 UDP, 2224 TCP |
| K3S | 6443 TCP, 8472 UDP |
| MONITOR | 9100, 9090, 3000, 3100, 8086 TCP |
| TORRENT | 6881–6889 TCP/UDP |
| VPN | 41641 UDP (Tailscale) |

---

## UniFi Network Lists (Port Groups)

These are the actual port groups defined in UniFi → Firewall & Security → Network Lists.
They are referenced by name in firewall rules.

| List name | Ports | Notes |
| --- | --- | --- |
| `admin` | 22, 80, 443, **8006**, **8007** | SSH + web UIs including Proxmox and PBS |
| `k3s-admin` | 111, 2049, 3260, 9100, 9500 | rpcbind, NFS, iSCSI, node_exporter, Longhorn |
| `storage` | 111, **2049**, 22, 80, 443 | Admin access to storage nodes |
| `dns` | 53, 853 | DNS + DoT |

> [!WARNING]
> The `storage` list in UniFi currently shows port **2048** — this is likely a typo.
> NFS is **2049**. Verify and correct in UniFi → Firewall & Security → Network Lists → storage.

> [!NOTE]
> `admin` needs **8006** (Proxmox web UI) and **8007** (PBS web UI) added if not already done.

---

## Management (10.10.10.0/24)

*Admin plane. Reaches everything. Nothing initiates into it.*

> [!DANGER]
> **UniFi zone-based firewall intercepts intra-VLAN traffic.** Without an explicit
> `MGMT → MGMT ALLOW`, your own Mac on 10.10.10.x cannot reach pve-srv nodes or
> the controller VM on the same subnet. This was the root cause of the June 2026 lockout.
> The `MGMT → MGMT` row MUST be the first rule — before any DENY.

> [!CAUTION]
> **Rule order within LAN IN is global.** Placing `ANY → MGMT DENY` early in the
> list blocks VPN → MGMT, MGMT → MGMT, and everything else. The row order in this
> table reflects the required priority order in UniFi.

| Priority | Source | Destination | Services | Intent |
| --- | --- | --- | --- | --- |
| **1** | **MGMT** | **MGMT (10.10.10.0/24)** | **ANY** | **Intra-VLAN admin traffic — prevents self-lockout** |
| 2 | MGMT | K3S (10.10.30.0/24) | SSH, K3S | Admin control |
| 3 | MGMT | STORAGE (10.10.40.0/24) | SSH, WEB | Admin access to TrueNAS + PBS web UIs only |
| 4 | MGMT | TORRENT (172.16.20.0/24) | SSH | Admin access only |
| 5 | MGMT | VPN (10.10.80.0/24) | SSH | Admin access |
| 6 | MGMT | PROVISIONING (10.10.99.0/24) | SSH | PXE control |
| 7 | MGMT | WAN | CORE, WEB | Updates, DNS, NTP |
| 8 | VPN (10.10.80.0/24) | MGMT | SSH, WEB | Remote admin — must be above the ANY DENY below |
| **last** | ANY | MGMT | **DENY** | No inbound initiation from other zones |

> [!IMPORTANT]
> The `VPN → MGMT` allow row is duplicated here (it also appears in the VPN section)
> to document that it must sit **above** the `ANY → MGMT DENY` in the global LAN IN
> rule list. If these are separate rules in UniFi, ensure VPN → MGMT has a lower rule
> number (higher priority) than ANY → MGMT DENY.

> [!NOTE]
> The UXG Max gateway (10.10.10.254) must reach the controller VM (10.10.10.10) on
> ports 8080 and 8443. This is covered by `MGMT → MGMT ANY` above — do not remove it.

> [!DANGER] **The controller VM (10.10.10.10) is a single point of failure.**
> If any rule blocks traffic TO 10.10.10.10, the UXG Max loses its controller and
> cascades into WAN loss — making the gateway (.1) and all pve-srv nodes appear dead
> even though they are up. Devices that don't route through the UXG (e.g. Synology
> at .15 reachable via L2) will still be up, which is how you can distinguish a
> controller-loss cascade from a true network failure.
> Never create a rule with destination `10.10.10.10` or `10.10.10.0/24` that isn't
> already covered by an explicit ALLOW above it.

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
| K3S (HA IP only) | IoT | any | Home Assistant device control |
| IoT | WAN | CORE, WEB | Device updates and cloud APIs |
| IoT | RFC1918 | **DENY** | No internal access |
| ANY | IoT | **DENY** | No inbound access |

> [!NOTE] Home Assistant Source IP
> Scope the `K3S → IoT` allow rule to Home Assistant's specific pod IP or LoadBalancer IP
> rather than the entire 10.10.30.0/24. Home Assistant uses `hostNetwork: true` in the
> k3s deployment, so it runs on the worker node's IP. Use the worker node IPs
> (10.10.30.11–13) as the source, or assign HA a fixed LoadBalancer IP via MetalLB.

> [!NOTE] mDNS / Bonjour
> For Home Assistant to discover devices via mDNS (Chromecast, Apple TV, Sonos, etc.),
> mDNS traffic must cross the VLAN boundary. Enable **mDNS forwarding** in UniFi
> (Network → [VLAN] → Advanced → Enable multicast DNS) for both VLAN 30 and VLAN 50.
> If UniFi's mDNS forwarder is unreliable, deploy an Avahi container on Athena bridged
> across both VLANs as an mDNS reflector.

> [!NOTE] IoT WiFi SSID
> Create a dedicated SSID in UniFi bound to VLAN 50. Keep it completely separate from
> your main SSID. Devices on the IoT SSID will never see your laptop, phone, or any
> management host — even on the same physical access point.

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

> [!WARNING]
> `VPN → MGMT` must be placed **before** `ANY → MGMT DENY` in the global LAN IN list.
> If it fires after the deny, VPN access to MGMT is silently blocked — this contributed
> to VPN being useless during the June 2026 lockout.

| Source | Destination | Services | Intent |
| --- | --- | --- | --- |
| VPN | MGMT | SSH, WEB | Admin access — ensure this is above ANY→MGMT DENY |
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
> **Owner access is intentionally broad** — full reach to MGMT, k3s, and Storage via Tailscale is correct for solo use.
>
> **Before sharing Tailscale access with anyone else**, restrict them via Tailscale ACLs in the admin console (tailscale.com/admin/acls):
> - Tag the shared device (e.g. `tag:limited`)
> - Write a grant that allows only specific subnets or IPs (e.g. Grafana IP only, no MGMT)
> - Owner device keeps `*` access; tagged guests get scoped access
> Never hand out your Tailscale auth key — generate a separate reusable key per person and revoke it when done.

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




***

# Break-Glass: Recovering from a Firewall Lockout

> [!CAUTION]
> This is the procedure used when firewall rules locked out the entire network —
> WAN dropped, Proxmox nodes unreachable on 22/8006, cloud portal unavailable,
> and Tailscale down.
>
> **Confirmed symptom:** Mac on 10.10.10.x could not reach .1–.10, but *could* reach
> 10.10.10.15 (Synology). This rules out a blanket MGMT→MGMT deny — the issue was
> targeted at the infrastructure IP range.
>
> **Most likely root cause:** A firewall rule blocked traffic to the controller VM
> (10.10.10.10 / dock-prod). The UXG Max lost controller contact, which cascaded
> into WAN loss and made the pve-srv nodes and gateway (.1) appear unreachable.
> Devices not dependent on the controller (Synology at .15) stayed accessible.

### Diagnosis Sequence

1. **Confirm nodes are alive, not dead** — `filtered` ports mean a firewall is
   dropping packets, not that hosts are down:
```sh
   nmap -Pn -p 22,8006 10.10.10.1 10.10.10.2 10.10.10.3 10.10.10.4
```
   `Host is up` + `filtered` = nodes alive, firewall blocking. (-Pn skips ping
   discovery, which is itself blocked.)

2. **Check ARP to confirm L2 reachability**:
```sh
   arp -a | grep "10.10.10"
```
   Note: same-subnet traffic is switched at L2 and normally bypasses the UniFi
   router firewall — BUT UniFi's zone-based firewall CAN intercept intra-VLAN
   traffic depending on zone definitions. This is what bit us.

3. **Identify what's actually down**: WAN down at the same time as firewall
   changes = not coincidental. Controller VM (10.10.10.10) showing ARP
   `incomplete` = controller unreachable = UXG Max lost its brain.

### Recovery Path (no cloud portal, no working SSH password for UXG Max)

> [!IMPORTANT] Why this path works
> The UniFi cloud portal needs WAN (down). SSH to the UXG Max needs the device
> password (not recorded). But traffic from a Proxmox HOST to its own VMs goes
> through the local Linux bridge (vmbr0) and NEVER touches the UniFi firewall.
> That's the way in.

1. **Physical console** (keyboard + monitor) on pve-srv-1.

2. **SSH from the Proxmox host to the controller VM** — bypasses UniFi firewall
   entirely since it's local bridge traffic:
```sh
   ssh hughboi@10.10.10.10
```

3. **Locate the controller + mongo containers**:
```sh
   docker ps
```
   Stack: `unifi_controller` (jacobalberty/unifi) + `unifi_mongo` (mongo:3.6).
   MongoDB is a SEPARATE container, default port 27017 (NOT 27117).

4. **Restore from backup via the API** (one-liner — fastest fix). Backups live at
   `/home/hughboi/data/unifi/backup/autobackup/`:
```sh
   curl -sk -c /tmp/c -XPOST https://localhost:8443/api/login \
     -H "Content-Type: application/json" \
     -d '{"username":"USER","password":"PASS"}' \
   && curl -sk -b /tmp/c -XPOST https://localhost:8443/api/s/default/cmd/restore \
     -F "file=@/home/hughboi/data/unifi/backup/autobackup/BACKUP_FILENAME.unf"
```
   `rc: ok` = accepted. The controller auto-restarts and applies the backup.

5. **Watch the controller come back up**:
```sh
   docker logs -f unifi_controller
```
   Wait for log flood to settle (~60–90s). UXG Max auto-reconnects and pulls the
   pre-firewall config. WAN returns on its own.

### Alternative: Disable rules directly in MongoDB (if no clean backup)

> [!NOTE] Zone-based firewall stores rules in a DIFFERENT collection
> The legacy `firewallrule` collection was EMPTY in our case (returned
> matchedCount: 0). Zone-based rules live in `trafficrule` / `trafficrulegroup`.
> Always check collection names first.

```sh
# List collections to find the right one
sudo docker exec -it unifi_mongo mongo unifi --eval "db.getCollectionNames()"

# Disable zone-based rules (use single quotes so $set isn't shell-expanded)
sudo docker exec -it unifi_mongo mongo unifi \
  --eval 'db.trafficrule.updateMany({}, {"$set": {"enabled": false}})'

# Push config to gateway
docker restart unifi_controller
```

### Lessons / Prevention

- [x] **ALWAYS make firewall changes from unifi.ui.com**, never the local
      controller — the cloud portal survives a self-inflicted lockout (this is
      only true while WAN is up; if a rule kills WAN, even this fails).
- [x] **Never block traffic to the controller VM (10.10.10.10)** — if the UXG
      Max can't reach its controller, it can cascade into WAN loss. Covered by
      the `MGMT → MGMT ANY` rule now documented in the Management section.
- [ ] **Record the UXG Max SSH device password** in Vaultwarden — would have
      been a faster recovery path than the console → VM → docker chain.
- [x] **Take a manual backup before every firewall change** — `autobackup` is
      what saved us. Also consider a manual snapshot immediately before any change.
- [x] **`ALLOW MGMT → MGMT` is now rule priority 1** in the Management section —
      this was the missing rule that caused the June 2026 lockout. Zone-based
      firewall intercepts intra-VLAN traffic; without this, your own Mac on
      10.10.10.x cannot reach any other MGMT host.
- [x] **`established/related` is rule #1 in LAN IN** — documented at the top
      of this file. Verify this in UniFi after any restore.