# audit-users

User and privilege audit across all hosts. Reports sudo-capable users, passwordless accounts, recently created/modified accounts, and SSH authorized keys.

## What it does

- Lists all users with sudo access and flags any not in `expected_sudo_users`
- Reports accounts with no password set
- Finds accounts created or modified in the last 30 days
- Dumps `authorized_keys` for all users so you can verify no unexpected keys exist

Read-only — makes no changes.

## Run

```sh
cd ansible/playbooks/ubuntu/audit-users
ansible-playbook -i <inventory> main.yaml
```

## Schedule

Monthly as a standing security check. Run immediately if you suspect unauthorized access.
