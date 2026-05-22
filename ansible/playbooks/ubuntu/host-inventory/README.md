# host-inventory

Generates a markdown snapshot of every host: OS version, kernel, CPU, RAM, disk layout, uptime, IP addresses.

## What it does

Collects Ansible facts plus `lscpu`, `lsblk`, and disk usage into a structured markdown report saved to `/tmp/host-inventory.md` on the controller. Read-only — makes no changes.

## Run

```sh
cd ansible/playbooks/ubuntu/host-inventory
ansible-playbook -i <inventory> main.yaml
cat /tmp/host-inventory.md
```

## Use cases

- Before/after hardware changes to document the diff
- Living infrastructure documentation
- Checking kernel versions across the fleet before a planned upgrade
