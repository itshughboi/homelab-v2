# TrueNAS

Default admin user: **truenas_admin**. Networking (bridge `br0`): [Networking.md](Networking.md).
ZFS pool + maintenance: [ZFS.md](ZFS.md).

> **Drive split on pve-srv-1:** the **2× Samsung 870 EVO 4TB SSD** are passed through to the
> TrueNAS VM (ID 105, below). The **2× Seagate ST8000DM004 8TB HDD** are passed through to the
> **PBS** VM, not TrueNAS — see [../PBS/README.md](../PBS/README.md).

### Disk Passthrough (Samsung SSDs → TrueNAS VM 105)
1. On server node shell, install lshw
``` 
apt install lshw
```
2. Get full disk info grab serial numbers
```
lshw -class disk -class storage
```

sda: ZR15MQS4 
sdb: ZR15JMEQ

sdc: S6PJNJ0W401496L scsi1
sdd: S6PJNJ0W401500P scsi1

3. Get device ID for these drives and find the lines that has the serial #
```
..... /dev/disk/by-id/ata-xxxxxxxxx-xxxxx_xxx ......
```

4. Pass disks through with console. Replace with actual value. 
```
qm set 105 -scsi1 /dev/disk/by-id/ata-xxxxxxxxx-xxxxx_xxx
```

> [!Replace -scsi1 everytime, incrementing the value by 1]
> 
> 

ata-Samsung_SSD_870_EVO_4TB_S6PJNJ0W401496L
ata-Samsung_SSD_870_EVO_4TB_S6PJNJ0W401500P

ata-ST8000DM004-2U9188_ZR15MQS4 = sda 8 tb
ata-ST8000DM004-2U9188_ZR15JMEQ = sdb 8 tb

5. Add serial number in proxmox
```
sudo nano /etc/pve/qemu-server/105.conf
```
6. Add serial number variable
```
,serial=
```
