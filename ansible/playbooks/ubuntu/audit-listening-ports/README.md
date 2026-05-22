# audit-listening-ports

Audits TCP/UDP ports listening on non-loopback interfaces across all hosts and flags anything unexpected.

## What it does

Uses `ss` to list all listening sockets, filters to non-loopback addresses, and compares against an expected allowlist. Anything not in the list gets flagged in the report. Read-only — makes no changes.

## Run

```sh
cd ansible/playbooks/ubuntu/audit-listening-ports
ansible-playbook -i <inventory> main.yaml
```

## Expected ports (default allowlist)

`22` (SSH), `80/443` (Traefik), `8006` (Proxmox UI), `53` (DNS), `67` (DHCP), `8025` (Mailrise)

Edit `expected_ports` in vars to match your environment before running against all hosts.

## Schedule

Monthly, or after any infrastructure change that could expose new services.
