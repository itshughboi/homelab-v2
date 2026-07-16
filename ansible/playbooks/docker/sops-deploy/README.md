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

**Services with anonymous (unnamed) Docker volumes can silently attach to the
wrong data.** This playbook's deploy task (`community.docker.docker_compose_v2`)
doesn't set an explicit `project_name` — it defaults to the basename of
`project_src` (i.e. `apps/docker/<service>`), same as plain `docker compose`.
If a service's `compose.yaml` has anonymous volumes (`volumes: data:` with no
`name:` key), Compose prefixes them with that project name at runtime. This is
fine as long as the project name never changes — but if it ever does (a
directory rename, or an explicit `project_name` ever gets added to this
playbook), Compose creates **brand-new empty volumes** instead of attaching to
the service's real data, with no error. Before the *first* `sops-deploy` run
for any service holding real data, verify: `cd apps/docker/<service> &&
docker compose config | tail -5` should show the volume names you expect
already exist (`docker volume ls`). See
[docs/Backup-Recovery.md](../../../../docs/Backup-Recovery.md#ad-hoc-back-up-a-docker-named-volume-before-a-risky-change)
for the full pre-cutover check-and-backup pattern.

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

### Config-as-secret services (no separate .env)

Some services (e.g. `mailrise`) bake secrets directly into a config file instead
of reading them from env vars — there's no `.env` to encrypt, the config file
itself is the secret. For those, commit `<filename>.<ext>.sops` instead of (or
alongside) `.env.sops` — this playbook auto-detects and decrypts any `*.sops`
file (other than `.env.sops`) straight to its real filename
(`mailrise.conf.sops` → `mailrise.conf`) on the target host. No migrate-script
equivalent exists yet — encrypt by hand:

```sh
sops --encrypt --config .sops.yaml \
  --filename-override apps/docker/<service>/<filename>.<ext>.sops \
  apps/docker/<service>/<filename>.<ext> \
  > apps/docker/<service>/<filename>.<ext>.sops
git add apps/docker/<service>/<filename>.<ext>.sops
git commit -m "chore(<service>): add SOPS-encrypted <filename>"
git push
```

`--filename-override` is required — SOPS matches `.sops.yaml`'s creation rules
against the *input* file path by default, and the real input here
(`mailrise.conf`, no `.sops` in the name) won't match `apps/docker/.*\.sops$` on
its own. `sops-migrate.sh` does the same thing for `.env` under the hood.

Unlike `.env`, decrypted config-secret files are **not** deleted from the target
host after deploy — services like mailrise read their config continuously from
disk, not just at container-start, so it needs to stay in place. Keep the plaintext
copy out of `.gitignore` exceptions for that service directory regardless.

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
