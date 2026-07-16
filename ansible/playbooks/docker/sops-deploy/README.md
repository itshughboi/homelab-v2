Deploy a Docker Compose service with SOPS-encrypted secrets, driven from Semaphore —
no manual SSH into the target host required.

## How it works

1. Pulls the latest `homelab` repo on the target host (so `compose.yaml` is current)
2. Decrypts `apps/docker/<service>/.env.sops` **on the controller (Athena)** — the
   private age key never leaves Athena, the target host never needs `sops`/`age`
   installed at all
3. Copies the decrypted `.env` to the target host (mode `0600`), runs
   `docker compose up -d`, then deletes the decrypted copy from both the target
   host and the controller

Equivalent of `./scripts/sops-run.sh <service> up -d` run by hand, but from
Semaphore instead of a manual SSH session.

## Gotchas

**Never run this via Semaphore's "Dry Run" option.** Dry run puts Ansible in
check mode, and `ansible.builtin.command` (used for the `sops` decrypt step)
doesn't support check mode — it silently reports "skipping" instead of running,
which cascades into the next task failing with "Could not find or access
`/tmp/sops-deploy-<service>.env` on the Ansible Controller". This looks like a
playbook bug but isn't one — a normal (non-dry-run) run works fine.

## Requirements

The service must already be migrated to SOPS — `apps/docker/<service>/.env.sops`
has to exist and be committed. If it doesn't, run once from a machine with the age
private key (e.g. Athena):

```sh
cd ~/homelab/apps/docker/<service>
# create/decrypt .env with real values first, then:
cd ~/homelab
./scripts/sops-migrate.sh <service>
git add apps/docker/<service>/.env.sops
git commit -m "chore(<service>): add SOPS-encrypted .env"
git push
```

## Usage

```sh
ansible-playbook -i inventory.yaml main.yaml -e service=gatus
```

**As a Semaphore Task Template:** add `service` as a Survey Variable (prompted on
each run), so one template deploys any migrated service — don't create a separate
template per service.

## Adding a new target host

Add it to `inventory.yaml` under `docker_hosts`. No `sops`/`age` install needed on
the new host — decryption always happens on the controller.
