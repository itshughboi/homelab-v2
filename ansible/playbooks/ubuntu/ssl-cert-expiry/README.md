# ssl-cert-expiry

Checks TLS certificate expiry on all homelab HTTPS endpoints and alerts before they expire.

## What it does

Probes each endpoint with `openssl s_client`, extracts the `Not After` date, and calculates days remaining. Sends ntfy notification for certs expiring within the warning window.

| Days remaining | Alert level |
|---|---|
| ≤ 30 | Warning |
| ≤ 14 | Critical (urgent ntfy) |

## Run

```sh
cd ansible/playbooks/ubuntu/ssl-cert-expiry
ansible-playbook -i inventory.yaml main.yaml
```

## Endpoints checked

All `*.hughboi.cc` and `*.hughboi.vip` services — defined in the `endpoints` var in the playbook. Add new services there as you deploy them.

## Schedule

Daily in Semaphore. cert-manager auto-renews at 30 days — this catches any renewal failure before users see browser certificate warnings.

## Notes

Runs on `localhost` (the Ansible controller) — no SSH needed. All checks are outbound HTTPS probes.
