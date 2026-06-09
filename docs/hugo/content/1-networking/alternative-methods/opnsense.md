---
title: "[ARCHIVED] OPNsense"
---

# [ARCHIVED] OPNsense

> **Status: Archived placeholder.** No content — kept in case OPNsense is evaluated in the future.


# DEPRECATED

Setup steps:
1. Setup network interfaces
2. Go through setup wizard on GUI by plugging into either LAN port or switch attached to LAN interface
	1. WAN should be set to DHCP
	2. Configure Unbound DNS and use that as resolver (or point to Adguard or PiHole). Otherwise, use public DNS
3. Check for updates
4. Setup VLANs

### Storage
- I typically choose UFS to install OPNsense on (local-lvm). I think you should go ZFS if you will just use the 1 disk without any sort of RAID tech, but if I want to set it up on a RAID technology, i can pass through 2 disks, and then use UFS

### Network
1. Setup virtual bridges for each physical interface. To allow High Availability and proper security best practices, you don't want to use the default bridge (vmbr0). 
	1. **Data Center -> Node -> Network**
		1. Setup WAN virtual bridge (vmbr1) to bind to the physical NIC of WAN
		2. Setup LAN virtual bridge (vmbr2) to bind to the physical NIC of LAN
		3. Setup another LAN virtual bridge (vmbr3) for HA & VLANs (vmbr3)



Known working config:

| Name   | Type           | Autostart | VLAN Aware | Ports/Slaves | CIDR          | Gateway    | Comment |
| ------ | -------------- | --------- | ---------- | ------------ | ------------- | ---------- | ------- |
| eno1   | Network Device | N         | N          |              |               |            | 2.5 GbE |
| enp4s0 | Network Device | N         | N          |              |               |            | 1 GbE   |
| vmbr0  | Linux Bridge   | Y         | N          | eno1         | 10.10.10.3/24 | 10.10.10.1 | LAN     |
| vmbr1  | Linux Bridge   | Y         | N          | enp4s0       |               |            | WAN     |


## Monitoring w/Prometheus, Alloy, & Grafana
See this video from Christian Lempa: https://www.youtube.com/watch?v=F3mvWIPTPjY
