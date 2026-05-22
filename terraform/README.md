
### Bootstrap Clout-Init Template
**Prepare API Token**
1. SSH into node 1 and create a dedicated service account
```sh
# 1. Create a Terraform user
pveum user add terraform@pve --password YOUR_SECRET_PASSWORD

# 2. Give it Administrator permissions (simplest for homelab start)
pveum acl modify / -user terraform@pve -role Administrator

# 3. Generate the API Token
pveum user token add terraform@pve terraform-token --privsep 0
```

> [!IMPORTANT] Copy/Save the value it spits out. 
> This is Terraform's password. Can't see again. Copy it into Vaultwarden when possible

**Create Cloud-Init Template**
- Run these while still SSH'd into node 1
```sh
# Download Ubuntu 22.04 Cloud Image
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

# Create a VM (ID 9999) for the template
qm create 9999 --name "ubnt-cloud" --memory 4096 --net0 virtio,bridge=vmbr0

# Import the image to storage
qm importdisk 9999 noble-server-cloudimg-amd64.img local-lvm

# Configure VM to use the imported disk
qm set 9999 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-9999-disk-0
qm set 9999 --ide2 local-lvm:cloudinit
qm set 9999 --boot c --bootdisk scsi0
qm set 9999 --serial0 socket --vga serial0

# Force the VM to use the serial console for display
qm set 9999 --agent enabled=1

# resize to a larger size to 50 GB
qm disk resize 9999 scsi0 50G

# Convert it to a template
qm template 9999
```

---

## Terraform Modules

| Directory | Purpose |
|-----------|---------|
| [proxmox/](proxmox/) | VM provisioning — k3s masters, workers, longhorn nodes, Docker host |
| [unifi/](unifi/) | Unifi network config — firewall, VLANs, DHCP reservations, DNS records |
| [bind9/](bind9/) | DNS records (legacy — being replaced by AdGuard in k8s) |

## Usage

```bash
cd terraform/proxmox
cp terraform.tfvars.example terraform.tfvars
# Fill in terraform.tfvars with Proxmox API token and credentials
terraform init
terraform plan
terraform apply
```
