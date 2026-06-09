# Static IPs and MAC Reservations

> MAC reservations are set in UniFi under **Client Devices → Click Device → Settings → IP Settings (Fixed IP Address)**.
> All core infrastructure must have a static reservation — IPs should never change after provisioning.

---

## VLAN 99 — Provisioning (legacy, unused)

> Netboot was abandoned — nodes install via [Ventoy USB](../../../2-proxmox/provisioning/Ventoy.md).
> This reservation is no longer required; kept until the Libre Potato is repurposed. See the
> [post-mortem](../../Alternative%20Methods/Netboot/README.md).

| Device | MAC | IP | Notes |
| --- | --- | --- | --- |
| Libre Potato | b6:c4:ec:25:85:13 | 10.10.99.99 | Former netboot server — unused |

---

## VLAN 10 — Management (Proxmox Nodes)

| Name      | MAC               | IP         | NIC     |
| --------- | ----------------- | ---------- | ------- |
| pve-srv-1 | 04:7c:16:87:65:66 | 10.10.10.1 | enp42s0 |
| pve-srv-2 | c8:ff:bf:00:80:7c | 10.10.10.2 | enp4s0  |
| pve-srv-3 | 1c:83:41:40:ff:0b | 10.10.10.3 | —       |
| pve-srv-4 | c8:ff:bf:03:f3:50 | 10.10.10.4 | —       |

---

## VLAN 10 — Management (VMs and Services)

| Name      | IP          | Gateway      | Role                                                     |
| --------- | ----------- | ------------ | -------------------------------------------------------- |
| truenas   | 10.10.10.5  | 10.10.10.254 | NAS — management NIC (web UI, SSH)                       |
| pbs       | 10.10.10.6  | 10.10.10.254 | Proxmox Backup Server — management NIC (web UI, SSH)     |
| athena    | 10.10.10.8  | 10.10.10.254 | Bind9 DNS, Ansible, Terraform, Gitea, Semaphore, Traefik |
| dock-prod | 10.10.10.10 | 10.10.10.254 | Docker production host                                   |

---

## VLAN 40 — Storage

> [!NOTE]
> TrueNAS and PBS each have **two NICs**: VLAN 10 for management (web UI, SSH) and VLAN 40 for storage traffic (NFS, iSCSI, jumbo frames).
> Static IPs set directly on the VM — no gateway on the storage NIC (VLAN 40 is intra-node only).
> DNS must be configured statically on the storage NIC (`9.9.9.9`, `1.1.1.2`) — DHCP is disabled on VLAN 40.
> Set matching MAC reservations in UniFi for both NICs to prevent IP conflicts.

| Name    | IP         | Gateway | Role                          |
| ------- | ---------- | ------- | ----------------------------- |
| truenas | 10.10.40.5 | none    | NAS — storage NIC             |
| pbs     | 10.10.40.6 | none    | Proxmox Backup Server — storage NIC |

---

## VLAN 80 — VPN

| Name | IP | Notes |
| --- | --- | --- |
| vpn-gateway (tailscale) | 10.10.80.254 | Subnet router only |

---

## VLAN 30 — k3s

| Name | IP |
| --- | --- |
| k3s-master-1 | 10.10.30.1 |
| k3s-master-2 | 10.10.30.2 |
| k3s-master-3 | 10.10.30.3 |
| k3s-worker-1 | 10.10.30.11 |
| k3s-worker-2 | 10.10.30.12 |
| k3s-worker-3 | 10.10.30.13 |
| k3s-api-vip | 10.10.30.30 |
| k3s-longhorn-vip | 10.10.30.50 |
| k3s-longhorn-1 | 10.10.30.51 |
| k3s-longhorn-2 | 10.10.30.52 |
| k3s-longhorn-3 | 10.10.30.53 |
| MetalLB range start | 10.10.30.60 |
| traefik-vip | 10.10.30.65 |
| pihole-vip | 10.10.30.69 | *(test/reference only — not in active use; AdGuard is the DNS filter, see [DNS.md](../Networks/DNS.md))* |
| MetalLB range end | 10.10.30.99 |
