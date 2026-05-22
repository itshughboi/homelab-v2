# snapshot-prune

Deletes old `ansible-*` snapshots across all Proxmox nodes. Companion to `snapshot-all-vms`.

## What it does

Removes snapshots matching the `ansible-` prefix that are older than `max_age_days` (default: 7). Dry-run mode is on by default — preview before committing.

## Run

```sh
cd ansible/playbooks/proxmox/snapshot-prune

# Preview (dry run, default)
ansible-playbook -i inventory.yaml main.yaml

# Actually delete
ansible-playbook -i inventory.yaml main.yaml -e dry_run=false
```

## When to run

A few days after a maintenance window, once you've confirmed everything is working correctly. Snapshots consume disk on the local Proxmox storage — don't leave them accumulating.

## Notes

- Only removes snapshots matching the `ansible-` prefix — manually created snapshots are untouched
- `max_age_days: 7` — adjust if you want a longer safety window
