---
title: "pve-srv-4"
---



| Spec         | Value                     |
| ------------ | ------------------------- |
| CPU          | Ryzen 7 5825U (8c / 16t)  |
| RAM          | 32 GB @ 2667 MHz DDR4     |
| BIOS Version | AR5000-MI -.33 - 12/18/24 |


| Name   | Alt Name | Type           | Active | Autostart | VLAN Aware | Ports/Slaves | CIDR          | Gateway      | Comment                                  |
| ------ | -------- | -------------- | ------ | --------- | ---------- | ------------ | ------------- | ------------ | ---------------------------------------- |
| eno1   |          | Network Device | No     | No        | No         |              |               |              | 1 GbE (right)                            |
| enp4s0 |          | Network Device | No     | No        | No         |              |               |              | 2.5 GbE (left) << closest to power cable |
| vmbr0  |          | Linux Bridge   | Yes    | Yes       | Yes        | enp4s0       | 10.10.10.4/24 | 10.10.10.254 |                                          |
| wlp4s0 |          | Network Device | No     | No        | No         |              |               |              | WiFi — not used                          |


C8FFBF03F350 (Realtek)
C8FFBF03F351 (Intel I226-V)