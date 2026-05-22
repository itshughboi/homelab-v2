# Packer

VM template builds for Proxmox. Templates are the base images Terraform clones to create every VM in the cluster.

## Templates

| Directory | OS | VM ID | Purpose |
|-----------|----|-------|---------|
| [proxmox-iso-ubuntu/](proxmox-iso-ubuntu/) | Ubuntu 24.04 LTS | 9999 | Golden image for all k3s and Docker host VMs |

## Build flow

```
Packer builds VM template (ID 9999) on Proxmox
       │
       └─ Terraform clones ID 9999
              ├─ k3s-master-1/2/3   (IDs 601–603)
              ├─ k3s-worker-1/2/3   (IDs 611–613)
              ├─ k3s-longhorn-1/2/3 (IDs 621–623)
              ├─ athena             (ID 100)
              └─ dock-prod          (ID 110)
```

## Usage

```bash
cd packer/proxmox-iso-ubuntu

# First time: copy and fill in variables
cp proxmox.pkrvars.sh.example proxmox.pkrvars.sh
$EDITOR proxmox.pkrvars.sh

# Build the template
./build.sh
```

See [proxmox-iso-ubuntu/README.md](proxmox-iso-ubuntu/README.md) for full setup instructions.

## Rebuild cadence

Rebuild the template when:
- A new Ubuntu 24.04.x point release is available
- New packages need to be baked in (open-iscsi for Longhorn, etc.)
- The Proxmox QEMU guest agent needs updating

Existing running VMs are not affected by a template rebuild — Terraform clones on `apply` only.
