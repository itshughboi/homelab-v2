# cluster-update

Rolling `apt upgrade` + `pveupgrade` across all 4 Proxmox nodes, one at a time. Migrates VMs off a node before upgrading, reboots if needed, and waits for cluster rejoin before moving to the next node.

## What it does

For each node in inventory order (least critical first):
1. Migrates all running VMs to other nodes
2. Runs `apt update && apt upgrade -y` + `pveupgrade`
3. Reboots if a new kernel was installed
4. Waits for the node to rejoin the Proxmox cluster
5. Moves to the next node

## Run

```sh
cd ansible/playbooks/proxmox/cluster-update
# Dry run first (default) — shows what would happen
ansible-playbook -i inventory.yaml main.yaml

# Actually run
ansible-playbook -i inventory.yaml main.yaml -e dry_run=false
```

## Important

- Requires at least 2 nodes up so VMs have somewhere to migrate
- Snapshot VMs first: `ansible-playbook -i ../snapshot-all-vms/inventory.yaml ../snapshot-all-vms/main.yaml`
- Node order in inventory: pve-srv-4 → 3 → 2 → 1 (primary last)
- If a node fails mid-upgrade, the playbook halts — remaining nodes are untouched

## Schedule

Run quarterly or when a security patch requires it. Always snapshot first.
