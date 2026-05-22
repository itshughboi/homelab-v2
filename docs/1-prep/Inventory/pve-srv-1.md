
**Role:** Storage, Docker, management VMs (Athena, TrueNAS, PBS, Tailscale, Unifi)
**IP:** 10.10.10.1

| Spec        | Value                              |
| ----------- | ---------------------------------- |
| CPU         | Ryzen 5 5600x (6c / 12t)           |
| RAM         | 96 GB                              |
| Kernel      | Linux 6.17.9-1-pve                 |
| PVE Manager | pve-manager/9.1.5/80cf92a64bef6889 |

#### NIC's

| Name | Alt Name | Type | Active | VLAN Aware | Comment |
| --- | --- | --- | --- | --- | --- |
| enp35s0f0 | | Network Device | No | No | |
| enp35s0f1 | | Network Device | No | No | |
| enp36s0 | | Network Device | No | No | 1 GbE On Board |
| enp42s0 | enx047c16876566 | Network Device | Yes | No | 2.5 GbE On Board — active trunk NIC |
| enp43s0f0 | | Network Device | No | No | Right Most (4/4) |
| enp43s0f1 | | Network Device | No | No | Right (3/4) |
| enp43s0f2 | | Network Device | No | No | Left (2/4) |
| enp43s0f3 | | Network Device | No | No | Left Most (1/4) |
| enp4s0f0 | | Network Device | No | No | |
| enp4s0f1 | | Network Device | No | No | |
| enp4s0f2 | | Network Device | No | No | |
| enp4s0f3 | | Network Device | No | No | |
| enp5s0 | enx047c16876567 | Network Device | No | No | |
| vmbr0 | | Linux Bridge | Yes | No | Not used |
| vmbr1 | | Linux Bridge | Yes | Yes | VLAN-aware bridge — slaves enp42s0 — 10.10.10.1/24 |

> **Current setup:** Single 2.5 GbE NIC (`enp42s0`) trunking all VLANs via 802.1Q on `vmbr1`.
> The 4-port card (`enp43s0f0–f3`) is available for future LACP bonding or dedicated storage NIC.
> See [[LACP - MLAG]] for when that becomes viable.
