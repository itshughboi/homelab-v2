### Credetials
Default admin user: **truenas_admin**

### Disk Passthrough
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
