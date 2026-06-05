# Firewall Rules

> [!CAUTION]
> ALLOW rules must be ABOVE DENY rules in UniFi (rule order matters).
> Verify correct rule direction (LAN IN vs LAN OUT).

> [!WARNING]
> **Always make firewall changes from [unifi.ui.com](https://unifi.ui.com) (cloud portal), not the local controller.**
> If you create a zone or rule that blocks your own VLAN, the local controller becomes unreachable and you lock yourself out.
> The cloud portal connects independently of your local network and lets you undo the mistake.
> Learned this the hard way creating the MGMT zone.

---

## First — Two Things Before Any Rules

1. **Enable "Block inter-VLAN traffic"** in UniFi Network settings. This is the baseline default-deny. ALLOW rules below punch specific holes in it.

2. Add this as the **very first rule in LAN IN**, before any VLAN-specific rules:
   `ALLOW ALL → ALL  state: established, related`
   This permits return traffic for connections you initiated, without needing explicit rules in both directions. Without it, outbound ALLOWs work but responses get dropped.

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

## Architecture

| Layer | VLAN | Trust Level | Description |
| --- | --- | --- | --- |
| Control Plane | Management (10) | Fully trusted | Admin origin, full infrastructure control |
| Compute Plane | k3s (30) | Semi-trusted | Runs workloads and applications |
| Data Plane | Storage (40) | Highly restricted | Critical data services (NFS, PBS, etc.) |
| Devices | IoT (50) | Untrusted | Smart home devices — isolated, HA-accessible only |
| Edge / Risk Zone | Torrent (49) | Untrusted | Internet-facing, high-risk traffic |
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
| MGMT | STORAGE (10.10.40.0/24) | SSH, WEB | Admin access to TrueNAS + PBS web UIs only |
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
> and Tailscale down. Root cause: new firewall rules blocked traffic to the
> UniFi controller VM (Athena/dock-prod, 10.10.10.10), which cascaded into the
> UXG Max losing controller contact and dropping WAN.

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

- [ ] **ALWAYS make firewall changes from unifi.ui.com**, never the local
      controller — the cloud portal survives a self-inflicted lockout (this is
      only true while WAN is up; if a rule kills WAN, even this fails).
- [ ] **Never block traffic to the controller VM (10.10.10.10)** — if the UXG
      Max can't reach its controller, it can cascade into WAN loss.
- [ ] **Record the UXG Max SSH device password** in Vaultwarden — would have
      been a faster recovery path than the console → VM → docker chain.
- [ ] **Take a manual backup before every firewall change** (this is what saved
      us — `autobackup` had a clean pre-change snapshot).
- [ ] Add an explicit `ALLOW MGMT → MGMT` rule above `ANY → MGMT DENY` so admin
      traffic within the management VLAN is never caught by the deny.
- [ ] Keep `established/related` as rule #1 in LAN IN.