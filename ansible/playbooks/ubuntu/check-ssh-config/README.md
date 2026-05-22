# check-ssh-config

Audits SSH daemon configuration across all hosts and fails the play if critical misconfigurations are found.

## What it does

Checks that hardening settings are in place:
- `PasswordAuthentication no`
- `PermitRootLogin no`
- `PubkeyAuthentication yes`
- Login grace time and idle timeout configured
- Only expected public keys in `authorized_keys`

Fails (does not continue) if critical issues are found — this is intentional so Semaphore alerts you.

## Run

```sh
cd ansible/playbooks/ubuntu/check-ssh-config
ansible-playbook -i <inventory> main.yaml
```

## Schedule

Monthly. Run after the hardening playbook to verify nothing drifted.
