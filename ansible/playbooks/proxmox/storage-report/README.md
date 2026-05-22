# storage-report

Reports disk usage per storage pool across all Proxmox nodes and flags pools over a warning threshold.

## What it does

Queries each node's storage pools via `pvesh`, reports usage percentages, and lists which VMs/CTs are consuming the most space. Flags pools over the warning threshold. Read-only — makes no changes.

## Run

```sh
cd ansible/playbooks/proxmox/storage-report
ansible-playbook -i inventory.yaml main.yaml
```

## Schedule

Run monthly or any time you suspect storage is getting tight. Useful before provisioning new VMs to confirm capacity exists.
