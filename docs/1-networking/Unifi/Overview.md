Order of Operations
Build network -> Secure it -> Add services

1. Power on Unifi gateway, plug laptop into port 1 on LAN and go to default IP: **192.168.1.1**
2. Configure Unifi Gateway (in this order):
	1. WAN - DHCP
	2. DNS - 9.9.9.9, 1.1.1.1 (temporary for bootstrap; will switch to internal DNS later)
	3. VLANs
	4. LACP / MLAG (if applicable. See notes)
	5. Firewall
	6. DHCP PXE Boot 66/67
	7. MAC Reservations (Static IPs for core infra)
		1. Libre Potato → 10.10.99.99
		2. Proxmox servers
	8. Netboot provisioning


> [!NOTE] DNS Setup
> Configure DNS per-network (not at gateway level) for full control.
> Each network: Settings → Networks → [Network] → Advanced → DHCP Name Server → uncheck Auto.
> Enter all four in order: `10.10.10.10` (AdGuard), `10.10.10.9` (bind9 current), `10.10.10.8` (bind9 future/Athena), `9.9.9.9` (external fallback).
> Torrent (VLAN 49) exception: `9.9.9.9` only — internal IPs would break the airgap.
> See [index.md](docs/1-networking/README.md) DHCP/DNS section for full details.

> [!NOTE]
> This is the only thing that needs to be done MANUALLY in this guide. This is best done through UniFi's own UI. Ansible plugins aren't complete, and the preliminary network to even get Ansible able to connect to UniFi isn't up at this point either. Also, if I used Terraform, I would ONLY be able to manage it with Terraform — easy way to break everything. **Unifi UI is the way to go**
