# Hardware Inventory

| Node | CPU | RAM | Role |
| --- | --- | --- | --- |
| pve-srv-1 | Ryzen 5 5600x (6c/12t) | 96 GB | Primary node — NAS host candidate |
| pve-srv-2 | Ryzen 7 5800U (8c/16t) | 32 GB | k3s master-1 + worker-1 |
| pve-srv-3 | Ryzen 7 5825U (8c/16t) | 32 GB | k3s master-2 + worker-2 |
| pve-srv-4 | Ryzen 7 5700U (8c/16t) | 32 GB | k3s master-3 + worker-3 |
| Libre Potato | ARM | — | Permanent PXE netboot server — lives on VLAN 99 |
| UXG Max | — | — | Router/firewall — LAN MAC + WAN MAC in device file |

Per-node NIC layout and bridge config: [pve-srv-1.md](pve-srv-1.md) · [pve-srv-2.md](pve-srv-2.md) · [pve-srv-3.md](pve-srv-3.md) · [pve-srv-4.md](pve-srv-4.md)

---

## Planned NAS Build (pve-srv-1 upgrade)

When pve-srv-1 is replaced with a dedicated NAS box:

- Case: Jonsbo N6
- CPU: i5-13500
- RAM: 96–128 GB DDR4
- SATA Controller: Broadcom/LSI 9400-8i (8× SATA)
- **4× 4TB Samsung 870 QVO SSD** → 2+2 mirror VDEVs (fast pool)
- **4× 8TB WD Red Plus HDD** → 2+2 mirror VDEVs (bulk pool)
