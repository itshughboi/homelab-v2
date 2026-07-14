- [ ] Flash ventoy images and boot up each pc
- [ ] Move management VLAN to 10 (test)
- [ ] Get mini pcs inventory in Unifi/Assignments/Inventory
	- [ ] Update MAC Reservations after that
	- [ ] Verify which is 2.5 GbE and which is 1 GbE
- [ ] Configure/update with ansible playbook
- [ ] Do Adguard cutover when i have k3s adguard up [[docs/hugo/content/1-networking/unifi/networks/dns|dns]]
	- [ ] Couple things in here I need to configure, veryify, and change. Couple contradictions in what networks get what dns sesrvers
- [ ] Decide on if Proxmox should have VLAN 40 for PBS 
- [ ] Once monitoring is up and going, revisit [[docs/hugo/content/1-networking/unifi/security/logging|logging]] with Unifi
	- [ ] implement unifi honeypot


Things to do when i get more hardware:
- lacp
- dedicated storage NICs for all servers separate from management/corosync
- channel AI when I get unifi AP up and going