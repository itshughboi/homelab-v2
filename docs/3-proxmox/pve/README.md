## Notification Endpoint
email: alerts@hughboi.cc


## Updates
Datacenter -> Updates -> Refresh to update and then click Upgrade to upgrade. Must be root for this.
Can also login to shell and run apt update && apt dist-upgrade
Reboot if there is a kernel update



## VM Creation Default Values
**Machine Type**: Typically I can do i440fx, but if I need to do any hardware passthrough, a **q35** machine will be needed/recommended (IOMMU)
**Disks**: 
- SSD emulation (checked). Enables TRIM. Once something is marked for deletion, it can go back and reclaim that space

**CPU**:
- Type: Host. This grants it the full features of the CPU in this emulated setup

**Memory**:
- Ballooning Device: Unchecked. This will carve out a portion of your total RAM to this machine. If ballooning is on, it will dynamically allocate more RAM up to the theorteical max, but the reserve it takes from is shared through the host. Can run into issues if too many things have ballooning on and RAM gets overallocated.



## NIC's
#### **pve-srv-1** <br>
Intel 82575EB Gigabit Network Connection - 1C:86:0B:20:06:B8 <br>
Intel 82575EB Gigabit Network Connection - 1C:86:0B:20:06:B9 <br>

Intel Ethernet I350-T4 - 98:B7:85:1E:A0:22 - rightmost <br>
Intel Ethernet I350-T4 - 98:B7:85:1E:A0:23 - second to the right <br>
Intel Ethernet I350-T4 - 98:B7:85:1E:A0:24 - second to the left <br>
Intel Ethernet I350-T4 - 98:B7:85:1E:A0:25 - leftmost of the four <br>




## Cluster Setup
1. Manually boot first proxmox node from Ventoy. Enable SSH, and get to where the Web UI is accessible at https://IP:8006
2. Bootstrap a template Ubuntu machine via **cloud-init**.
   - Add SSH key
   - Set Network
4. Full clone the cloud-init template and install Ansible
5. Manually boot the rest of the proxmox nodes. Enable SSH, and get to where the Web UI is accessible at https://IP:8006
6. SSH into ansible machine + git pull ansible playbooks
7. Run the ansible proxmox-node-setup script

There should now be a working proxmox cluster with best security practices.




<br>
<br>
***

## Best Practices
1. Setup No-Subscription repository and run updates and upgrades
2. Setup attended-upgrades to happen and then setup automation to reboot every 2 weeks
3. Setup notifications
- Datacenter -> Notification Target -> Add -> Gotify (or SMTP <- can then send to apprise>)
- Change default Notification matcher to include the new Notification Target I just created
4. Issue TLS certificate
- I haven't got this to work. You need to go to Datacenter -> ACME and register and then apply it under Certificates to the nodes, but doesn't show for me for some reason
5. Add proxmox backup server backup and setup jobs.
-  Change notification mode to be: Notification system so it uses Gotify when it backups
- Retention: I believe retention should be done on proxmox backup server itself. If I'm worried, just match them
7. Enable PCI Passthrough
- Enable IOMMU in BIOS and within Proxmox
- VM has to be q35... NOT i440
8. New VM Setup
- If i am virtualizing windows, make sure VM type is set to windows and the correct version. You then will need to upload the VirtIO drivers. ALSO add TPM
- Qemu Agent: CHECKED
- Graphics card: VirtIO GPU << better performance in vm. Better in windows VM too >>
- Network Model: VirtIO
9. Create VM Templates
10. Setup Wake on LAN
- ethtool eth0 | grep "Wake-on" << make sure there is a letter 'g' >>
- enable WoL
```
ethtool -s enp4s0 wol g
```
- Make it persistent: sudo nano /etc/network/interfaces and add following:
```
post-up /usr/sbin/etholol -s enp4s0 wol g
```
- Find MAC from ``` ip a ```
- Create magic packet
```
brew install wakeonlan
wakeonlan ${MACADDRESS}
```

- Magic Packet Routing:
    - Magic packet on broadcast won't pass between networks
    - Use a machine that is connected to the destination network # << essentially subnet routing here >>
