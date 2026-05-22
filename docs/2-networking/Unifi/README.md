*Deployable with Ansible* 
- Management network needs DHCP option to point to netbootxyz machine to load iPXE
    - see for more info: iac\bootstrap\README.md   
- Each Proxmox node will need 3 virtual interfaces. `pve-srv-1` should have **2**+ physical NICs. See [[Proxmox Virtual Interfaces]]
	1. Management / Cluster VLAN
	2. Storage VLAN - MTU 9000
- Apply QoS to **VLAN 20** with QoS to prioritize Corosync traffic.
- Allow Jumbo Frames on **VLAN 40** << 6x more data per packet. Maaximizes throughput + Minimizes overhead 

> [!DANGER] Jumbo Frames
> Every device on VLAN 40 (Proxmox, Truenas, PBS) MUST support and be configure for **MTU 9000** or else packets will drop. Jumbo packets can't go over the internet which is why we created this VLAN specifically for internal storage


### Additional Notes:

**VLAN 20**: Corosync is very sensitive to latency. If I'm flooding a NIC with backups or storage retrieval, it can cause jitter and fuck with Proxmox and may cause a Fencing (Hard Reboot) event. Problem is that I enjoy seeing the webUI at 10.10.10.x/24. This has **NO GATEWAY**. Only internal routing.<br>

**VLAN 40**:  Similar to VLAN 20, PBS or Longhorn can saturate the management network which can slow down SSH or Athena VM. Has a gateway (`10.10.40.254`) for outbound package updates only — firewall blocks all other outbound. **Jumbo Frames (MTU 9000)** required end-to-end.


