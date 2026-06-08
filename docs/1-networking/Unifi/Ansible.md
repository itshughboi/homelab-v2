# UniFi Ansible Integration

> [!WARNING] NOT THE ACTIVE APPROACH
> UniFi is configured manually through the UI — set it once, back it up, leave it alone.
>
> **Why not Ansible:** The UniFi UI evolves faster than the `community.general` collection keeps up. Plugin methods fall behind, expected parameters change, and things that worked before silently break. For a system that rarely needs to change and where a misconfigured rule can lock you out, chasing plugin compatibility isn't worth it.
>
> This doc exists as a reference if you ever need to automate a full UniFi rebuild from scratch. For day-to-day management: use the UI. For recovery: use the backup.

---

## Prerequisites

1. **Local admin account in UniFi** — create one specifically for Ansible. Cloud accounts won't work.
2. **Install the UniFi collection** on the Ansible machine:

```sh
ansible-galaxy collection install community.general
```

---

## Playbook

**Location:** `ansible/playbooks/unifi/`

| File | Purpose |
| --- | --- |
| `site.yaml` | Main playbook — entry point |
| `group_vars/all.yaml` | All VLAN/network definitions (edit this to add/change networks) |
| `group_vars/unifi.yaml` | Controller credentials — must be Ansible Vault encrypted |
| `inventory.yaml` | UniFi controller host |

**Run locally:**
```sh
cd ansible/playbooks/unifi
ansible-playbook site.yaml --ask-vault-pass
```

**Run from Semaphore:** point a Task Template at `ansible/playbooks/unifi/site.yaml` with the vault password stored in Semaphore's Key Store.

Encrypt credentials before first use:
```sh
ansible-vault encrypt group_vars/unifi.yaml
```

## What Ansible Can Automate

Using `community.general` UniFi modules:

- VLAN / network creation (all VLANs in [Networks/README.md](Networks/README.md))
- DHCP option configuration (Option 66/67 on VLAN 99 for PXE)
- Firewall rule creation
- Switch port profiles

## What Ansible Cannot Do Here

- **Proxmox virtual interfaces** — `vmbr0.10`, `vmbr0.20`, `vmbr0.40` are Proxmox-side config, not UniFi. These are handled by the [[Proxmox Virtual Interfaces]] Ansible playbook run against the Proxmox nodes directly.
