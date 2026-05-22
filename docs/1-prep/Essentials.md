- Netbootxyz configured and plugged into provisioning Access Port
- Unifi gateway configured.
- Unifi DHCP pointing to netboot `ipxe.efi`
- For all servers:
	- PXE boot enabled
	- Boot order: PXE first
	- Secure Boot: OFF

**Boot Files**
- Each node needs a per-node TOML at `http://10.10.99.99:8080/proxmox/pve-srv-X.toml`
- Each node's MAC must be mapped to its hostname in `local.ipxe`
- Each node needs a MAC reservation in UniFi for VLAN 10

These files live in the IAC repo. Push changes and the Libre Potato picks them up within 5 minutes via the git pull timer.


**Verify netboot is serving correctly:**
```sh
curl -I http://10.10.99.99:8080/ipxe.efi
curl -I http://10.10.99.99:8080/proxmox/pve-srv-1.toml
```
Expected: `HTTP/1.1 200 OK` on both.