# Bootstrap

One-time tooling for provisioning bare-metal hardware from zero — before Terraform or Ansible can take over. Run these tools once per piece of hardware, then shut them down.

---

## Contents

| Directory | Purpose |
|-----------|---------|
| [netbootxyz/](netbootxyz/) | PXE boot server — automated network install of Proxmox on bare metal |

---

## Overview

The bootstrap process gets you from an unpowered server to a fully configured Proxmox node without touching a USB stick. The sequence is:

```
Bare metal
   │
   └─ PXE boot via netboot.xyz  →  Proxmox installed + SSH reachable
                                         │
                                         └─ Hand off to Terraform + Ansible
```

Full step-by-step: see [docs/SETUP_GUIDE.md](../docs/SETUP_GUIDE.md).

---

## netboot.xyz

Runs as a Docker container on any machine with network access to the provisioning VLAN. Provides:

- **TFTP (port 69)** — serves the iPXE binary to booting clients
- **HTTP (port 8080)** — serves iPXE scripts and Proxmox autoinstall preseed files
- **Web UI (port 3000)** — menu configuration and TFTP diagnostics

### Quick start

```bash
cd bootstrap/netbootxyz

# Place Proxmox kernel and initrd in assets/proxmox/ first (see netbootxyz/README.md)

docker compose up -d
```

Then configure your DHCP server to point PXE clients at this machine (DHCP options 66/67).

See [netbootxyz/README.md](netbootxyz/README.md) for:
- Full boot chain explanation
- How to extract the Proxmox installer kernel/initrd from the ISO
- UniFi DHCP configuration
- How to add a new server (new `.toml` + MAC mapping)
- Preseed file reference (`disk_list`, `root_password`, gateway)
- Troubleshooting

### Servers provisioned

| Hostname | IP | Role |
|----------|-----|------|
| pve-srv-1 | 10.10.10.1 | Proxmox node |
| pve-srv-2 | 10.10.10.2 | Proxmox node |
| pve-srv-3 | 10.10.10.3 | Proxmox node |
| pve-srv-4 | 10.10.10.4 | Proxmox node |

### After all nodes are provisioned

1. Stop the netboot.xyz container — it is no longer needed:
   ```bash
   cd bootstrap/netbootxyz && docker compose down
   ```
2. Continue in [terraform/proxmox/](../terraform/proxmox/) to provision VMs
3. Then [ansible/playbooks/ubuntu/new-host-bootstrap/](../ansible/playbooks/ubuntu/new-host-bootstrap/) to configure each VM
4. Then [ansible/playbooks/kubernetes/k3s/](../ansible/playbooks/kubernetes/k3s/) to install k3s
