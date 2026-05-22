## Setup
Go to Ubuntu Cloud Images Releases. Find the LTS I want. Navigate into the 'current' directory. Find the amd.img and right click and hit 'copy link address' and then on local storage in Proxmox query that URL.
https://cloud-images.ubuntu.com/

#### Shell
```
qm create 5003 --memory 8192 --core 4 --name ubnt-cloud-noble --net0 virtio,bridge=vmbr0
```

##### Verify iso exists
```
cd /var/lib/vz/template/iso/
ls
```

##### Add iso to that machine
```
qm importdisk 5003 noble-server-cloudimg-amd64.img local-lvm
qm set 5003 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-5003-disk-0
```

##### Expand Hard drive
```
qm disk resize 5003 scsi0 50G
```

##### Attaching dvd drive essentially
```
qm set 5003 --ide2 local-lvm:cloudinit
```

```
qm set 5003 --boot c --bootdisk scsi0
qm set 5003 --serial0 socket --vga serial0
```

##### Proxmox GUI

##### Hardware
1. Click on the Hard Disk. Turn on **SSD Emulation** so that it can do S.M.A.R.T. 
2. On Memory turn off **ballooning memory**

##### Cloud-init
- Change username to **hughboi**
- Add public key from my automation machine AND from proxmox. I want to add it from the proxmox host so that I can **VNC** into it from console. I can create new ssh keys if I want, but I just use the default ssh-rsa
***
!! In production I would want to specify separate specific keys for ^^
***
- Make sure IP Config is set to DHCP. Else it will clone each VM with same IP. Instead, take the hardware device after I do a Full Clone and then set a **DHCP Reservation**


##### VM Clone
- Right click on template and hit **Full Clone**


***

### Cloud Init SSH
1. Make sure my public key is put into cloud-init of machine
2. Console into machine and edit ssh file
```
sudo nano /etc/ssh/sshd_config
```
3. Uncomment PubkeyAuthentication yes
4. Uncomment AuthorizedKeyFile
5. Restart service
```
sudo systemctl restart ssh
```

##### Permissions
```
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
chown -R hughboi:hughboi ~/.ssh
```


### Specifying ssh private key
```
ssh -i ~/.ssh/ansible hughboi@10.10.30.1
```


##### Debugging
```
ssh -vvv -i ~/.ssh/ansible hughboi@10.10.30.1
```


***

##### Create new SSH keypair
```
ssh-keygen -t ed25519
```
^^ this crypto algorithm is becoming the new standard

##### Copy over public key
```
ssh-copy-id hughboi@SERVERIP/HOSTNAME
```


### Pubkey Authentication (Including Raspberry Pi Imager)
- If i keep seeing this after editing /etc/ssh/sshd_config, there's probably an override somewhere. Common things I've seen is Cloud Init overriding it under **/etc/ssh/sshd_config.d/50-cloud-init.conf** and password authentication might be turned off there

