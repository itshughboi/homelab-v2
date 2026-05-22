1. Install the following locally if I don't have netbootxyz active yet. We need to turn your existing machine into the ops center for deployment until we can get our new manager Athena (ansible + terraform) provisioned onto Proxmox
	1. Docker
	2. Terraform (optional)
	3. Ansible
	4. Git
2. Create or clone my bootstrap repo locally
```sh
	git clone https://github.com/itshughboi/iac.git
```
1. Generate SSH Keys for the data center (injects into every node)





- In this setup I am using a dedicated netboox box. Could also just run on my macbook
	- Plug macbook into the provisioning port on my Unifi switch. It will be assigned IP of **10.10.99.100/24** on VLAN **99**
	- If not using Unifi, or DHCP Boot options not setup, ssh/console into router to set those options. See here: [[Guide]]
	- Make sure that devices have PXE boot enabled in BIOS
		- I had to go into Network Stack: Enabled before I could enable PXE boot