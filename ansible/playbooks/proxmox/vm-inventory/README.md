# vm-inventory

Generates a full VM and container inventory report across all Proxmox nodes as a markdown table.

## What it does

Queries each node via `pvesh` and collects: node, VMID, name, status, CPU cores, RAM (MB), disk (GB), OS type, uptime. Saves output to `/tmp/vm-inventory.md` on the Ansible controller.

## Run

```sh
cd ansible/playbooks/proxmox/vm-inventory
ansible-playbook -i inventory.yaml main.yaml
cat /tmp/vm-inventory.md
```

## Use cases

- Before/after infrastructure changes to confirm the diff
- Living documentation of what's running and where
- Quick reference when planning VM migrations or resource allocations
