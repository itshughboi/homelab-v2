CPU: Ryzen 7 5800U with Radeon Graphics (8 c / 16 t)
RAM: 32 GB
Kernvel version: Linux 6.8.12-13-pve (2025-07-22T10:00Z)
Manager version: pve-manager/8.4.10/293f4abc4b22fa08

| Name   | Alt Name | Type           | Active | Autostart | VLAN Aware | Ports/Slaves | CIDR          | Gateway      | Comment                                  |
| ------ | -------- | -------------- | ------ | --------- | ---------- | ------------ | ------------- | ------------ | ---------------------------------------- |
| eno1   |          | Network Device | No     | No        | No         |              |               |              | 1 GbE (right)                            |
| enp4s0 |          | Network Device | No     | No        | No         |              |               |              | 2.5 GbE (left) << closest to power cable |
| vmbr0  |          | Linux Bridge   | Yes    | Yes       | Yes        | enp4s0       | 10.10.10.2/24 | 10.10.10.254 |                                          |
| wlp4s0 |          | Network Device | No     | No        | No         |              |               |              | iFi — not used                           |
