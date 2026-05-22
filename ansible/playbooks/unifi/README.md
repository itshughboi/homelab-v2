


## Unifi
- Management network needs DHCP option to point to netbootxyz machine to load iPXE
    - see for more info: iac\bootstrap\README.md   
- Each Proxmox node will need 3 virtual interfaces. `pve-srv-1` should have **2**+ physical NICs.
	1. Management / Cluster VLAN
	2. Storage VLAN - MTU 9000
- Apply QoS to **VLAN 20** with QoS to prioritize Corosync traffic.
- Allow Jumbo Frames on **VLAN 40** << 6x more data per packet. Maaximizes throughput + Minimizes overhead 

> [!DANGER] Jumbo Frames
> Every device on VLAN 40 (Proxmox, Truenas, PBS) MUST support and be configure for **MTU 9000** or else packets will drop. Jumbo packets can't go over the internet which is why we created this VLAN specifically for internal storage

| Virtual Interface | Target VLAN | Gateway      | MTU  |DHCP 67
| :---------------- | :---------- | ------------ | ---- |-----------
| **vmbr0.10**      | 10          | 10.10.10.254 | 1500 |10.10.99.99
| **vmbr0.20**      | 20          | None         | 1500 |
| **vmbr0.40**      | 40          | None         | 9000 |
<br>

- Create the following networks in Unifi << CAN BE DONE WITH ANSIBLE

| Name         | VLAN ID | CIDR           | Notes                  |
| ------------ | ------- | -------------- | ---------------------- |
| Management   | 1       | 10.10.10.0/24  | SSH, Web UI, Unifi, Bind9
| Cluster      | 2       | 10.10.20.0/24  | Corosync               | 
| k3s          | 3       | 10.10.30.0/24  |                        |   
| Storage      | 4       | 10.10.40.0/24  | TrueNAS, PBS, Longhorn |
| VPN          | 8       | 10.10.80.0/24  | Tailscale              |
| Torrent      | 49      | 172.16.20.0/24 |                        |
| Provisioning | 99      | 10.10.99.0/24  | Netboot                |


### Additional Notes:

**VLAN 20**: Corosync is very sensitive to latency. If I'm flooding a NIC with backups or storage retrieval, it can cause jitter and fuck with Proxmox and may cause a Fencing (Hard Reboot) event. Problem is that I enjoy seeing the webUI at 10.10.10.x/24. This has **NO GATEWAY**. Only internal routing.<br>

**VLAN 40**:  Similar to VLAN 20, PBS or Longhorn can saturate the management NIC which can slow down SSH or Athena VM. This has **NO GATEWAY**. Only internal routing. **Jumbo Frames** enabled
<br>
<br>

### Ansible Secrets
group_vars/unifi.yaml should be encrypted with Ansible Vault!
```sh
ansible-vault encrypt group_vars/unifi.yml
```
It will ask you for a "Vault Password." From then on, the file is scrambled. When you run your playbook, you just add --ask-vault-pass, and Ansible decrypts the password in memory to talk to the API.