# snapshot-all-vms

Snapshots every running VM across all 4 Proxmox nodes. Run before any maintenance window.

## What it does

Creates a snapshot named `ansible-YYYY-MM-DD` on every running VM. Templates and VMs that already have today's snapshot are skipped. Processes one node at a time to avoid API contention.

## Run

```sh
cd ansible/playbooks/proxmox/snapshot-all-vms
ansible-playbook -i inventory.yaml main.yaml
```

## Notes

- Snapshots include RAM state by default (can be changed in vars)
- Takes ~2–5 min depending on number of VMs and RAM sizes
- Sends ntfy notification on completion
- Run `snapshot-prune` a few days later once you've confirmed the maintenance was successful

## When to run

- Before `cluster-update` (rolling Proxmox upgrade)
- Before any VM migration or storage reconfiguration
- Before major Terraform changes to existing VMs
