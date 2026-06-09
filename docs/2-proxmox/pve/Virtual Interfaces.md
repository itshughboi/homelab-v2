# Proxmox Virtual Interfaces

Each Proxmox node needs virtual interfaces for each VLAN it participates in.
`pve-srv-1` requires 2+ physical NICs due to the storage VLAN needing MTU 9000.

---

## Virtual Interface Table

| Virtual Interface | Target VLAN | Gateway | MTU | Notes |
| --- | --- | --- | --- | --- |
| vmbr1.10 | 10 | 10.10.10.254 | 1500 | Management |
| vmbr1.20 | 20 | None | 1500 | Cluster / Corosync — no gateway, QoS enabled |
| vmbr1.40 | 40 | None | 9000 | Storage — Jumbo Frames, no gateway |

> [!DANGER] Jumbo Frames on VLAN 40
> Every device on VLAN 40 (Proxmox, TrueNAS, PBS) must be configured for MTU 9000
> end-to-end: switch ports, NICs, bridges, and VMs. Partial MTU support causes
> silent packet loss. Jumbo packets cannot traverse the internet.

---

## Notes Per Interface

**vmbr1.20 (Cluster):**
- Corosync is extremely sensitive to latency
- If a NIC gets saturated with backup/storage traffic, jitter can cause a Fencing event (hard reboot)
- No gateway — completely internal
- IGMP Snooping enabled on the switch port — keeps Corosync multicast surgical, not flooded

**vmbr1.40 (Storage):**
- PBS and Longhorn can saturate the management NIC if on the same interface
- This VLAN provides physical separation of storage traffic
- **No gateway — intentional.** All storage traffic is intra-VLAN: Proxmox nodes talk directly to TrueNAS and PBS on the same /24, no routing needed. OS updates and any other outbound traffic leave via vmbr1.10 (Management). Adding a gateway here would create a routing table entry that could cause Proxmox to try routing traffic through the storage interface — don't add one.
- Jumbo Frames required end-to-end

---

## pve-srv-1 Bridge Config

`vmbr1` is the VLAN-aware trunk on `enp42s0` (2.5 GbE on-board). The node's management IP sits directly on the bridge.

| Name     | Type                 | Ports/Slaves | CIDR          | Gateway      | MTU  | Comment                                            |
| -------- | -------------------- | ------------ | ------------- | ------------ | ---- | -------------------------------------------------- |
| vmbr0    | Linux Bridge         | —            | —             | —            | 1500 | Not used — default empty bridge                    |
| vmbr1    | Linux Bridge (trunk) | enp42s0      | 10.10.10.1/24 | 10.10.10.254 | 9000 | VLAN-aware — management IP lives on bridge directly |
| vmbr1.20 | VLAN                 | vmbr1        | —             | —            | 1500 | Cluster / Corosync — create if not present         |
| vmbr1.40 | VLAN                 | vmbr1        | —             | —            | 9000 | Storage — Jumbo Frames — create if not present     |

> [!WARNING] **TODO — TrueNAS and PBS not yet on VLAN 40**
> Both VMs are currently on Management (VLAN 10) only. Each needs a **second NIC** added for VLAN 40 storage traffic.
> Keep the existing VLAN 10 NIC — it stays as the management interface (web UI, SSH).
>
> Steps for each VM (TrueNAS and PBS):
> 1. In Proxmox: VM → Hardware → Add → Network Device → Bridge: `vmbr1`, VLAN Tag: `40`, MTU: `9000`
> 2. Inside TrueNAS: configure the new NIC with static IP `10.10.40.5`, no gateway, DNS `9.9.9.9`
> 3. Inside PBS: configure the new NIC with static IP `10.10.40.6`, no gateway, DNS `9.9.9.9`
> 4. Add MAC reservations in UniFi for both new NICs (see [MAC Reservations.md](../../1-networking/Unifi/Assignments/MAC%20Reservations.md))
> 5. Update the `TORRENT → TrueNAS NFS` firewall rule destination from `10.10.10.5` → `10.10.40.5` (see Firewall/Rules.md)
> 6. Verify jumbo frames end-to-end: `ping -M do -s 8972 10.10.40.5`

> [!IMPORTANT]
> `vmbr1` itself must be set to MTU 9000. The parent bridge MTU must be >= the highest sub-interface MTU.
> If vmbr1 stays at 1500, vmbr1.40 will silently drop oversized packets even if the sub-interface shows 9000.

> [!WARNING] **Every new VM must have MTU explicitly set in its network_device config.**
> VM NICs inherit the bridge MTU if left unset. Since vmbr1 is MTU 9000, any VM without an explicit MTU
> will advertise 9000 to its guest OS — even if it's only on VLAN 10 (Management), which is 1500.
>
> | VM type | NIC | MTU to set |
> | --- | --- | --- |
> | Management VMs (athena, dock-prod, unifi) | VLAN 10 | `1500` |
> | k3s masters / workers / longhorn | VLAN 30 | `1500` |
> | TrueNAS / PBS — management NIC | VLAN 10 | `1500` |
> | TrueNAS / PBS — storage NIC | VLAN 40 | `9000` |
>
> In Terraform: set `mtu = 1500` or `mtu = 9000` in the `network_device` block.
> In Proxmox UI: Hardware → Network Device → Edit → MTU field.

**Available but unused NICs on pve-srv-1:**
- `enp43s0f0-3` — 4-port PCIe card (Right Most / Right / Left / Left Most). Best candidate for dedicated cluster or storage NICs when needed.
- `enp35s0f0/f1` — 2-port card, unused
- `enp36s0` — 1 GbE on-board, unused
- `enp4s0f0-3` — 4-port card, unused

---

## pve-srv-2 / pve-srv-3 / pve-srv-4 Bridge Config

Mini PCs — identical hardware, identical bridge layout. Only the management IP differs.
`vmbr0` is the trunk on `enp4s0` (2.5 GbE, **left port**, closest to the power cable).
`eno1` (1 GbE, right port) and `wlp4s0` (WiFi) are unused.

| Name     | Type                 | Ports/Slaves | CIDR              | Gateway      | MTU  | Comment                                             |
| -------- | -------------------- | ------------ | ----------------- | ------------ | ---- | --------------------------------------------------- |
| vmbr0    | Linux Bridge (trunk) | enp4s0       | —                 | —            | 9000 | VLAN Aware<br>MTU 9000 required to support vmbr0.40 |
| vmbr0.10 | VLAN                 | vmbr0        | 10.10.10.**x**/24 | 10.10.10.254 | 1500 | Management                                          |
| vmbr0.20 | VLAN                 | vmbr0        | —                 | —            | 1500 | Cluster / Corosync                                  |
| vmbr0.40 | VLAN                 | vmbr0        | —                 | —            | 9000 | Storage — Jumbo Frames                              |

| Node | Management IP |
| --- | --- |
| pve-srv-2 | 10.10.10.2/24 |
| pve-srv-3 | 10.10.10.3/24 |
| pve-srv-4 | 10.10.10.4/24 |

> [!NOTE]
> pve-srv-1 uses `vmbr1` as the trunk; pve-srv-2/3/4 use `vmbr0`. Different bridge names, same function — both are VLAN-aware with the same sub-interface structure.
