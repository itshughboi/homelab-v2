# vm-template-refresh

Downloads the latest Ubuntu Noble (24.04) cloud image and updates the Proxmox cloud-init VM template (ID 9999).

## What it does

1. Downloads the latest `ubuntu-noble-server-cloudimg-amd64.img` from Ubuntu's cloud image CDN
2. Imports it as a disk on pve-srv-1
3. Creates or recreates VM 9999 with: 2 vCPU, 2 GB RAM, cloud-init drive, QEMU guest agent
4. Converts the VM to a template

After running, clone VM 9999 to provision new VMs — either via Terraform or the Proxmox UI.

## Run

```sh
cd ansible/playbooks/proxmox/vm-template-refresh
ansible-playbook -i inventory.yaml main.yaml
```

## Schedule

Run quarterly or before a round of new VM provisioning to ensure new VMs start with a current base image. Terraform references VMID 9999 — do not change that ID.

## Notes

- Targets `pve-srv-1` only — templates are per-node in Proxmox
- The download is ~600 MB; takes 1–3 min depending on internet speed
- Existing VMs cloned from the old template are unaffected
