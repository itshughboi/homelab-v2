# Network Inventory — IPs, MACs & Placement (authoritative)

> **Single source of truth for addressing.** Every host, VM, and VIP with its IP, MAC (for
> statically-reserved devices), VLAN, and node placement lives here. Other docs link here
> rather than repeating tables — don't duplicate IPs elsewhere.
>
> **Resource sizing** (vCPU / RAM / disk) is the *other* source of truth, in the Terraform
> spec table: [2-proxmox/provisioning/README.md](../../../2-proxmox/provisioning/README.md#vm-spec-table).
>
> MAC reservations are set in UniFi under **Client Devices → [device] → Settings → Fixed IP
> Address**. All core infrastructure must have a static reservation — IPs never change after
> provisioning.

---

## VLAN 10 — Management: Proxmox nodes

Hardware detail per node: [Inventory/](Inventory/).

| Name      | MAC               | IP         | Trunk NIC | Hosts (VMs) |
| --------- | ----------------- | ---------- | --------- | ----------- |
| pve-srv-1 | 04:7c:16:87:65:66 | 10.10.10.1 | enp42s0   | athena, dock-prod, truenas, pbs, tailscale |
| pve-srv-2 | c8:ff:bf:00:80:7c | 10.10.10.2 | enp4s0    | k3s-master-1, k3s-worker-1, k3s-longhorn-1 |
| pve-srv-3 | 1c:83:41:40:ff:0b | 10.10.10.3 | enp4s0    | k3s-master-2, k3s-worker-2, k3s-longhorn-2 |
| pve-srv-4 | c8:ff:bf:03:f3:50 | 10.10.10.4 | enp4s0    | k3s-master-3, k3s-worker-3, k3s-longhorn-3 |

---

## VLAN 10 — Management: VMs & services

| Name      | IP          | Node      | Role |
| --------- | ----------- | --------- | ---- |
| truenas   | 10.10.10.5  | pve-srv-1 | NAS — management NIC (web UI, SSH); also on VLAN 40 |
| pbs       | 10.10.10.6  | pve-srv-1 | Proxmox Backup Server — management NIC; also on VLAN 40 |
| athena    | 10.10.10.8  | pve-srv-1 | Bind9 DNS (primary), Ansible, Terraform, Gitea, Semaphore, Traefik |
| dock-prod | 10.10.10.10 | pve-srv-1 | Docker host — UniFi controller, AdGuard, app workloads |

Gateway for all: `10.10.10.254`.

---

## VLAN 40 — Storage (no gateway, MTU 9000)

TrueNAS and PBS are **dual-homed** — VLAN 10 (above) for management, VLAN 40 for storage
traffic (NFS, iSCSI, jumbo frames). No gateway on the storage NIC; set matching MAC
reservations for both NICs to prevent conflicts.

| Name    | IP         | Node      | Role |
| ------- | ---------- | --------- | ---- |
| truenas | 10.10.40.5 | pve-srv-1 | NAS — storage NIC |
| pbs     | 10.10.40.6 | pve-srv-1 | Proxmox Backup Server — storage NIC |

---

## VLAN 80 — VPN

| Name                    | IP           | Node      | Role |
| ----------------------- | ------------ | --------- | ---- |
| vpn-gateway (tailscale) | 10.10.80.254 | pve-srv-1 | Tailscale subnet router only |

---

## VLAN 30 — k3s

IPs set statically via cloud-init at Terraform provision time (DHCP disabled on VLAN 30).
VIPs are MetalLB / control-plane virtual IPs, not pinned to a node.

| Name             | IP          | Node      | Type |
| ---------------- | ----------- | --------- | ---- |
| k3s-master-1     | 10.10.30.1  | pve-srv-2 | Control plane |
| k3s-master-2     | 10.10.30.2  | pve-srv-3 | Control plane |
| k3s-master-3     | 10.10.30.3  | pve-srv-4 | Control plane |
| k3s-worker-1     | 10.10.30.11 | pve-srv-2 | Worker |
| k3s-worker-2     | 10.10.30.12 | pve-srv-3 | Worker |
| k3s-worker-3     | 10.10.30.13 | pve-srv-4 | Worker |
| k3s-longhorn-1   | 10.10.30.51 | pve-srv-2 | Longhorn storage node |
| k3s-longhorn-2   | 10.10.30.52 | pve-srv-3 | Longhorn storage node |
| k3s-longhorn-3   | 10.10.30.53 | pve-srv-4 | Longhorn storage node |
| k3s-api-vip      | 10.10.30.30 | —         | Control-plane VIP |
| k3s-longhorn-vip | 10.10.30.50 | —         | Longhorn VIP |
| traefik-vip      | 10.10.30.65 | —         | MetalLB — ingress |
| pihole-vip       | 10.10.30.69 | —         | *test/reference only — not in active use; AdGuard is the DNS filter ([DNS.md](../Networks/DNS.md))* |

**MetalLB pool:** `10.10.30.60`–`10.10.30.99`.

---

## VLAN 99 — Provisioning (legacy, unused)

> Netboot was abandoned — nodes install via [Ventoy USB](../../../2-proxmox/provisioning/Ventoy.md).
> Reservation no longer required; kept until the Libre Potato is repurposed. See the
> [post-mortem](../../Alternative%20Methods/Netboot/README.md).

| Device       | MAC               | IP          | Notes |
| ------------ | ----------------- | ----------- | ----- |
| Libre Potato | b6:c4:ec:25:85:13 | 10.10.99.99 | Former netboot server — unused |
