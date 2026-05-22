# Static IPs and MAC Reservations

> MAC reservations are set in UniFi under **Settings → Networks → [VLAN] → DHCP**.
> All core infrastructure must have a static reservation — IPs should never change after provisioning.

---

## VLAN 99 — Provisioning

| Device | MAC | IP | Notes |
| --- | --- | --- | --- |
| Libre Potato | b6:c4:ec:25:85:13 | 10.10.99.99 | Netboot server — reserve this BEFORE provisioning any nodes |

---

## VLAN 10 — Management (Proxmox Nodes)

| Name      | MAC               | IP         | NIC     |
| --------- | ----------------- | ---------- | ------- |
| pve-srv-1 | 04:7c:16:87:65:66 | 10.10.10.1 | enp42s0 |
| pve-srv-2 | —                 | 10.10.10.2 | enp4s0  |
| pve-srv-3 | —                 | 10.10.10.3 | —       |
| pve-srv-4 | —                 | 10.10.10.4 | —       |

---

## VLAN 10 — Management (VMs and Services)

| Name | IP | Gateway | Role |
| --- | --- | --- | --- |
| truenas | 10.10.10.5 | 10.10.10.254 | NAS |
| pbs | 10.10.10.6 | 10.10.10.254 | Proxmox Backup Server |
| postgres-ha | 10.10.10.7 | 10.10.10.254 | |
| athena | 10.10.10.8 | 10.10.10.254 | Bind9 DNS, Ansible, Terraform, Gitea, Semaphore, Traefik |
| dock-prod (docker) | 10.10.10.10 | 10.10.10.254 | Docker production host |

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
| pihole-vip | 10.10.30.69 |
| MetalLB range end | 10.10.30.99 |
