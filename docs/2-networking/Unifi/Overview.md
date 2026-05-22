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


> [!NOTE] DNS: Two-Phase Setup
> Bootstrap: 9.9.9.9 / 1.1.1.1
> Post-Bind9: 10.10.10.x (Athena) / 9.9.9.9
> Remember to update both global DNS AND any per-VLAN DHCP overrides in UniFi.

> [!NOTE]
> This is the only thing that needs to be done MANUALLY in this guide. This is best done through UniFi's own UI. Ansible plugins aren't complete, and the preliminary network to even get Ansible able to connect to UniFi isn't up at this point either. Also, if I used Terraform, I would ONLY be able to manage it with Terraform — easy way to break everything. **Unifi UI is the way to go**
