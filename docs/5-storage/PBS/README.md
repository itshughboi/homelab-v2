### Download ISO
- Go to download page, copy link URL of iso (right click -> copy link) , then back in Proxmox I can import the ISO via URL
Link: https://www.proxmox.com/en/downloads/proxmox-backup-server/iso

### Pass through hard disks

1. Find the Disk ID
```
ls -l /dev/disk/by-id/ #find the corresponding values to hard dsisks
```

ata-ST8000DM004-2U9188_ZR15MQS4 = sda
ata-ST8000DM004-2U9188_ZR15JMEQ = sdb

1. df
```
qm set 106 -virtio2 /dev/disk/by-id/ata-ST8000DM004-2U9188_ZR15MQS4
qm set 106 -virtio3 /dev/disk/by-id/ata-ST8000DM004-2U9188_ZR15JMEQ
```

### TrueNAS Drives

/dev/sdc = ata-Samsung_SSD_870_EVO_4TB_S6PJNJ0W401496L
/dev/sdd = ata-Samsung_SSD_870_EVO_4TB_S6PJNJ0W401500P

#### Config

1. Repo + updates
	1. Administration -> Repostiories
		1. Disable enterprise and add 'No Subscription'.
		2. Back on Administration -> Updates, hit 'Refresh' to run apt-update and then 'Upgrade' for apt-upgrade (will open a shell and have to confirm 'Y')
2. Notifications
	1. Configuration -> Notifications
		1. Add SMTP
			1. server: 10.10.10.10
			2. Encryption: none
			3. Port: 8025
			4. From Address: pbs@hughboi.cc
			5. Recipients: root@pam (email is notify@mailrise.xyz)
			6. Additional: notify@mailrise.xyz choose this or ^^
		2. Gotify
			1. Server URL: https://gotify.hughboi.cc
			2. API: taken from Gotify
	2. Down below on **Notification Matchers** enable Mailrise + Gotify for the default rule


### Scripts to run - Proxmox Helper Scripts (optional)
https://community-scripts.github.io/ProxmoxVE/scripts?id=post-pbs-install
Run this in PBS shell: *specifically to get rid of subscription nag*
```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/post-pbs-install.sh)"
```


### Datastore
1. After disks have been passed through to the VM, create a new ZFS Pool under:
		Administration -> Storage / Disks -> ZFS -> Create ZFS. 
		Add as Data Store: Checked to auto create the datastore from this pool
		**Compression**: LZ4



### Add PBS to Proxmox VE
Datacenter -> Storage -> Add -> Proxmox Backup Server
```
ID: pbs
Server: 10.10.10.6
Username: changeme@pam
Datastore: Same name as datastore in PBS
Fingerprint: Snag this from PBS on Datastore -> Summary -> Show Connect Info
```

> [!Warning] USER ACCOUNT
> I've used root account in the past. This SHOULD be a new user on PBS that ONLY has access to datastores

**Encryption**: This SHOULD be turned on. However, I've run into issues restoring vm's with this enabled. I'm working on getting this working, but it should be ON moving forward


#### Backup Schedules
Datacenter -> Backup -> Add
```
Storage: pbs
Send email to: notify@mailrise.xyz
Send email: Always
Mode: Snapshot
```

**Retention**: CONFIGURE ONLY ON PBS. DO NOT HANDLE RETENTION IN PROXMOX ITSELF



### Jobs
**Prune**: Daily @ 9:30 PM
**GC**: Daily @ 8:45 AM
**Verify**: Daily. Skip verified. Reverify after 30 days
**Options**: Verify New Snapshots - YES



### Backup to TrueNAS via NFS
This is the preferred method of backing up data. Essentially PBS just acts as the middleman responsible for the deduplication, but then the actual data is going to be served over NFS to my TrueNAS so I get the full benefits of TrueNAS ZFS + PBS deduplication. 

1. SSH or get into console of PBS
2. Create a mount point
```
mkdir /mnt/truenas
```
3. 


4. Add to fstab
```
nano /etc/fstab
```
```
10.10.10.15:/volume1/PBS-Replica /mnt/truenas nfs vers=3,nouser,atime,auto,retrans=2,rw,dev,exec 0 0
```
##### Add Datastore Backing Path
Finally after verification that we can connect to this share, add a new datastore.
**Backing Path**: /mnt/truenas


### Backup to Synology



### Homepage integration
https://gethomepage.dev/widgets/services/proxmoxbackupserver/
USER NEEDS TO BE MADE IN PAM REALM NOT PVE!!!!!! << gave me lots of headaches
- Login with root user and then in cli do this:
```
proxmox-backup-manager user create homepage@pam --enable 1
```
- You will now see that user in UI
