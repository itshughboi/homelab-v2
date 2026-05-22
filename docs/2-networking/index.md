# 2. Networking

UniFi-based VLAN architecture that physically separates management, cluster, storage, and workload traffic. Configure manually once — never manage with Terraform (state drift makes it unusable).

---

## VLAN Architecture

| Name | VLAN ID | CIDR | MTU | Gateway | Notes |
| --- | --- | --- | --- | --- | --- |
| Management | 10 | 10.10.10.0/24 | 1500 | 10.10.10.254 | SSH, Web UIs, DNS |
| Cluster | 20 | 10.10.20.0/24 | 1500 | **none** | Corosync heartbeat only — no gateway, QoS DSCP 46. DHCP disabled. |
| k3s | 30 | 10.10.30.0/24 | 1500 | 10.10.30.254 | Workloads, MetalLB, Longhorn. DHCP pool starts at .200. |
| Storage | 40 | 10.10.40.0/24 | 9000 | **none** | TrueNAS, PBS, Longhorn — Jumbo Frames. DHCP disabled. |
| IoT | 50 | 10.10.50.0/24 | 1500 | 10.10.50.254 | Smart home devices — isolated, only Home Assistant can reach in |
| Torrent | 49 | 172.16.20.0/24 | 1500 | 172.16.20.254 | Airgapped from all RFC1918 |
| VPN | 80 | 10.10.80.0/24 | 1500 | 10.10.80.254 | Tailscale subnet router |
| Provisioning | 99 | 10.10.99.0/24 | 1500 | 10.10.99.254 | PXE boot only |

> [!IMPORTANT]
> **VLAN 20 = Cluster (Corosync) — no MTU change, no gateway.**
> **VLAN 40 = Storage — MTU 9000 mandatory, end-to-end, no exceptions.**
> These two are the most commonly confused. Trust this table.

### Why These Separate VLANs?

**VLAN 20 (Cluster, Corosync only):** Corosync is extremely latency-sensitive. If you flood the management NIC with backup or storage traffic, it causes jitter that can trigger a fencing event — a hard reboot of VMs. VLAN 20 is completely isolated with QoS (DSCP 46) so Corosync heartbeat packets always get priority. It has no gateway because nothing should be routing through it; it's purely intra-node heartbeat.

**VLAN 40 (Storage, Jumbo Frames):** PBS and Longhorn can saturate a management NIC, which slows down SSH to Athena and web UIs. Separate VLAN isolates this. Jumbo Frames (MTU 9000) give 6× more data per packet, maximizing throughput for NFS/iSCSI while minimizing CPU overhead from packet processing. No gateway because storage traffic should never leave this VLAN.

**VLAN 49 (Torrent, airgapped):** Completely isolated from all RFC1918 space. Torrent traffic goes WAN only. The entire 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 range is blocked from Torrent → internal.

**VLAN 50 (IoT, isolated):** Smart home devices — lights, locks, sensors, cameras — run outdated firmware and can't always be patched. This VLAN prevents any compromised device from reaching infrastructure. Home Assistant is the only service allowed to initiate connections into it. IoT devices cannot reach any RFC1918 address except through the HA → IoT firewall rule.

---

## MTU Verification (VLAN 40)

MTU 9000 is only as good as the weakest link. A misconfigured device causes **silent packet loss** — no errors, just degraded throughput. Verify end-to-end after any infrastructure change:

```sh
# Run from a k3s worker node (which is on VLAN 40) targeting TrueNAS
# -M do = prohibit fragmentation, -s 8972 = 9000 MTU - 28 byte IP+ICMP headers
ping -M do -s 8972 10.10.40.5

# If it fails, find the ceiling by stepping down:
ping -M do -s 4000 10.10.40.5
ping -M do -s 1472 10.10.40.5  # = standard 1500 MTU ceiling
```

MTU 9000 checklist (every item must be set — partial is broken):
- [ ] UniFi switch ports carrying VLAN 40 → MTU 9000
- [ ] USW trunk uplink port to UXG Max → MTU 9000
- [ ] Proxmox physical NIC: `ip link set enp42s0 mtu 9000` (persist in `/etc/network/interfaces`)
- [ ] Proxmox bridge `vmbr0`: `ip link set vmbr0 mtu 9000`
- [ ] VLAN interface `vmbr0.40`: `ip link set vmbr0.40 mtu 9000`
- [ ] TrueNAS: Storage → Network → Edit interface → MTU 9000
- [ ] k3s worker VLAN 40 NIC: verify with `ip link show eth1` (or whichever interface)

---

## Switch Port Assignments

**UXG Max (5 ports):**

| Port | Mode | VLAN | Role |
| --- | --- | --- | --- |
| WAN | — | — | ISP uplink |
| Port 2 | Access | 99 (untagged) | Libre Potato (permanent netboot) |
| Port 3 | Access | 99 (untagged) | Provisioning port — new nodes plug here during install |
| Port 4–5 | Trunk | All | Uplink to USW Flex Mini |

**USW Flex Mini (5 ports):**

| Port | Mode | VLAN | Role |
| --- | --- | --- | --- |
| Port 1 | Trunk | All | Uplink from UXG Max |
| Ports 2–5 | Trunk | 10, 20, 30, 40 | Proxmox nodes |

Set MTU 9000 on switch ports carrying VLAN 40. All other VLANs use default MTU 1500.

---

## DHCP / DNS Configuration

**VLAN 99 DHCP PXE options:**
- Option 66 (Boot Server): `10.10.99.99` (Libre Potato)
- Option 67 (Boot File): `ipxe.efi`

> [!NOTE]
> Newer UniFi firmware serves `ipxe.efi` via HTTP on port 8080, not TFTP.
> The netboot container must serve on port 8080. TFTP-only setups silently fail.

**DNS — two-phase approach:**
1. **Bootstrap:** set DHCP DNS to `9.9.9.9` / `1.1.1.1` temporarily for all VLANs
2. **Post-Bind9 cutover:** change DHCP DNS servers to `10.10.10.8` (Athena/Bind9) for all VLANs, update firewall rules to restrict DNS to Athena

---

## Firewall Rules

> [!CAUTION]
> Rule order is enforced top-down in UniFi. ALLOW rules must appear **above** DENY rules or they are never evaluated.

### Mandatory First Rules

Before any per-VLAN rules:

1. Enable **Block inter-VLAN traffic** in Network settings (your default-deny baseline)
2. Add as the **very first LAN IN rule**: `ALLOW ALL → ALL` with state `established, related`
   — without this, all return traffic for any outbound connection is dropped

### Service Groups (define once, reference in rules)

| Group | Ports |
| --- | --- |
| SSH | 22 TCP |
| CORE | DNS 53, DHCP 67/68, NTP 123 |
| WEB | 80, 443 TCP |
| BOOT | TFTP 69, HTTP 80, HTTPS 443 |
| STORAGE | NFS 2049, rpcbind 111, SMB 445, iSCSI 3260 |
| COROSYNC | 5404–5405 UDP, 2224 TCP |
| K3S | 6443 TCP, 8472 UDP |
| MONITOR | 9100, 9090, 3000, 3100, 8086 TCP |
| VPN | 41641 UDP (Tailscale) |

### Rules by VLAN

**Management (10):**
- MGMT → K3S: SSH, K3S
- MGMT → STORAGE: SSH, WEB, STORAGE, MONITOR
- MGMT → TORRENT: SSH
- MGMT → VPN: SSH
- MGMT → PROVISIONING: SSH, BOOT
- MGMT → WAN: CORE, WEB
- ANY → MGMT: **DENY**

**Cluster (20):**
- ANY → CLUSTER: **DENY** — Corosync is intra-VLAN only, nothing routes through here

**k3s (30):**
- MGMT → K3S: SSH, K3S
- K3S → STORAGE: STORAGE
- K3S → WAN: CORE, WEB
- K3S → MGMT: **DENY** (k3s cannot reach back to management)
- ANY → K3S: **DENY**

**Storage (40):**
- MGMT → STORAGE: SSH, WEB, STORAGE, MONITOR
- K3S → STORAGE: STORAGE
- STORAGE → WAN: CORE, WEB (package updates only)
- ANY → STORAGE: **DENY**

**Torrent (49):**
- MGMT → TORRENT: SSH
- TORRENT → WAN: CORE, WEB (all ports for torrenting)
- TORRENT → RFC1918: **DENY** (IP group: 10/8, 172.16/12, 192.168/16)
- ANY → TORRENT: **DENY**

**VPN (80):**
- VPN → MGMT: SSH, WEB
- VPN → K3S: K3S
- VPN → STORAGE: SSH, WEB
- VPN → WAN: VPN
- ANY → VPN: **DENY**

**Provisioning (99):**
- MGMT → PROVISIONING: SSH
- PROVISIONING → WAN: CORE, WEB, BOOT
- PROVISIONING → INTERNAL: **DENY**
- ANY → PROVISIONING: **DENY**

> [!WARNING]
> **Docker bypasses iptables.** Never use `--network=host` for services that should be firewalled.
> Traefik on dock-prod must bind explicitly to `10.10.10.10`, not `0.0.0.0`.
> Use the `DOCKER-USER` iptables chain for host-level restrictions.

---

## MAC Reservations / Static IPs

See [`Unifi/MAC Reservations.md`](Unifi/MAC%20Reservations.md) for the full table.

See [`Unifi/Static Clients.md`](Unifi/Static%20Clients.md) for the network assignment list.

---

## Tailscale (VPN / Remote Access)

Mode: **Subnet Router** — not Exit Node. Only homelab traffic routes through the tunnel.

```sh
tailscale up --advertise-routes=10.10.10.0/24,10.10.30.0/24 --accept-routes
```

Required static route in UniFi after Tailscale VM is running:
- Settings → Routing → Create New Route
- Destination: `100.64.0.0/10` (Tailscale CGNAT range)
- Type: Next Hop
- Next Hop: Tailscale VM IP on VLAN 80

> [!TIP]
> Running Tailscale in Subnet Router mode (not Exit Node) means only homelab-bound traffic routes through the tunnel. Your regular internet traffic still goes direct from your client, which is what you want.

---

## Proxmox Virtual Interfaces

Each Proxmox node needs these virtual interfaces. Configure in Proxmox UI → System → Network, or via Ansible `proxmox/virtual-interfaces` playbook.

| Interface | VLAN | MTU | Purpose |
| --- | --- | --- | --- |
| vmbr0 | — | 1500 | Physical uplink (must be VLAN-aware trunk) |
| vmbr0.10 | 10 | 1500 | Management |
| vmbr0.20 | 20 | 1500 | Cluster — apply QoS DSCP 46 to this interface |
| vmbr0.30 | 30 | 1500 | k3s workloads |
| vmbr0.40 | 40 | 9000 | Storage — Jumbo Frames |

pve-srv-1 needs 2+ physical NICs (one for management/workloads, one for dedicated storage if available).

---

## LACP / Bonding (Future)

pve-srv-1 currently uses a single 2.5 GbE NIC. LACP bonding is documented for when an enterprise-tier UniFi switch is available (MLAG requires enterprise tier).

See [`Unifi/LACP - MLAG.md`](Unifi/LACP%20-%20MLAG.md) for details.
