# SOPS + age: Docker Secrets Management

Complete reference for managing **Docker** service secrets (`apps/docker/**/.env.sops`) with SOPS
and age — the **live** SOPS scope (it's the only rule in `.sops.yaml`). For the Ansible/Terraform
scope see [Secrets_SOPS.md](Secrets_SOPS.md); for the GitOps overview + Kubernetes Sealed Secrets
see [index.md](index.md). The age key setup, multi-machine, rotation, and recovery flows below
apply to *all* scopes.

---

## Table of Contents

1. [What this is and why](#what-this-is-and-why)
2. [How it works](#how-it-works)
3. [First-time setup](#first-time-setup)
4. [Day-to-day workflow](#day-to-day-workflow)
5. [Migrating a service](#migrating-a-service)
6. [Deploying a service](#deploying-a-service)
7. [Editing secrets](#editing-secrets)
8. [Rebuilding from scratch](#rebuilding-from-scratch)
9. [Multiple machines](#multiple-machines)
10. [Key rotation and recovery](#key-rotation-and-recovery)
11. [How the CI check works](#how-the-ci-check-works)
12. [Troubleshooting](#troubleshooting)
13. [Cheatsheet](#cheatsheet)

---

## What this is and why

### The old problem

Every Docker service has a `.env.example` file listing what secrets it needs. To deploy, you copy it to `.env` and fill in 10–20 values by hand. On a fresh machine this takes 30–60 minutes and is easy to miss values. The `.env` files can never be committed to Git, so they only exist on disk.

### The new model

Secrets live in `.env.sops` files — encrypted versions of `.env` — committed to Git. On a fresh machine: clone the repo, restore one private key, and every service deploys immediately. No manual filling.

### The security improvement

| | Old (.env on disk) | New (.env.sops in Git) |
|---|---|---|
| Secrets in Git | ✗ Never safe | ✓ Encrypted (AES-256-GCM) |
| Fresh deploy time | 30–60 min manual | ~2 min |
| Secrets written to disk | ✓ Always (plaintext) | ✗ Never (memory only via exec-env) |
| Audit trail | None | Git commit history (key names visible) |
| Compromise of disk | All secrets exposed | Nothing useful (key required to decrypt) |

---

## How it works

### The two tools

**age** — generates an asymmetric keypair. Think SSH keys but specifically designed for file encryption.
- Private key: `~/.config/sops/age/keys.txt` — lives only on authorized machines and in Vaultwarden
- Public key: committed to `.sops.yaml` in the repo — safe to share, used only to encrypt

**SOPS** — encrypts files using the age public key. Unlike encrypting the whole file as a blob (like Ansible Vault), SOPS encrypts only the **values** while leaving the **keys** (variable names) readable.

### What an encrypted file looks like

```bash
# Original .env (never committed)
DOMAIN=https://vaultwarden.hughboi.cc
ADMIN_TOKEN=supersecrettoken123
SMTP_PASSWORD=myapppassword
SMTP_HOST=smtp.fastmail.com        # non-secret, but encrypted anyway
```

```bash
# After sops --encrypt → .env.sops (safe to commit)
DOMAIN=ENC[AES256_GCM,data:Tr4xK2mN...,iv:abc...,tag:xyz...,type:str]
ADMIN_TOKEN=ENC[AES256_GCM,data:9fGhJ3pL...,iv:def...,tag:uvw...,type:str]
SMTP_PASSWORD=ENC[AES256_GCM,data:7yHkM5nO...,iv:ghi...,tag:rst...,type:str]
SMTP_HOST=ENC[AES256_GCM,data:3wIlN7oP...,iv:jkl...,tag:mno...,type:str]

sops_version=3.9.0
sops_age_recipients=age1qyq...  ← your public key
sops_lastmodified=2026-05-19T...
sops_mac=ENC[AES256_GCM,data:...]  ← tamper detection
```

Key names (`DOMAIN=`, `ADMIN_TOKEN=`) are visible. Values are encrypted. This is intentional — it makes `git diff` useful (you can see which variables changed, just not what they changed to).

### The `.sops.yaml` config

```yaml
# .sops.yaml at repo root
creation_rules:
  - path_regex: apps/docker/.*\.sops$
    age: age1qyq...   ← your public key (safe to commit)
```

Any file matching `apps/docker/**/*.sops` is encrypted with that public key — not just
`.env.sops`. This also covers **config-as-secret** files, for services that bake secrets
directly into a config file instead of reading them from env vars (e.g. `mailrise.conf.sops`) —
see "Config-as-secret services" under
[`ansible/playbooks/docker/sops-deploy/README.md`](../../ansible/playbooks/docker/sops-deploy/README.md#config-as-secret-services-no-separate-env)
for the full pattern. SOPS reads this config automatically when you run it from anywhere in the repo.

> [!NOTE]
> The rule intentionally does **not** try to distinguish `.env.sops` from other `*.sops` files —
> both need the same age key, and an earlier attempt to exclude `.env.sops` via a regex
> lookbehind (`(?<!\.env)\.sops$`) failed outright: SOPS uses Go's RE2 regex engine, which
> doesn't support lookaround assertions at all (`can not compile regexp: invalid or unsupported
> Perl syntax`). One broad rule is simpler and works.

### How Docker Compose gets the secrets

Docker Compose interpolates `${VAR}` in compose files from two sources (in priority order):
1. Shell environment variables
2. `.env` file in the same directory

`sops-run.sh` decrypts `.env.sops` and exports each variable into its own shell environment
before calling `docker compose`, which then reads them from the environment. **No file is
written to disk.** (Originally implemented via `sops exec-env` — dropped after testing showed
it doesn't reliably honor `--input-type dotenv` against sops 3.9.0 and fails outright; the
script decrypts explicitly and exports line-by-line instead, same result.)

---

## First-time setup

### Install dependencies

```bash
# macOS
brew install sops age

# Ubuntu/Debian — do NOT use `apt install age`. apt's build is dynamically linked
# against glibc; it silently fails to exec inside any musl-based container (Alpine —
# e.g. Semaphore's own image). Neither sops nor age have an apt package worth using;
# get both as static release binaries:
AGE_VERSION=1.2.0
curl -fsSL "https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/age-v${AGE_VERSION}-linux-amd64.tar.gz" \
  | sudo tar -xz --strip-components=1 -C /usr/local/bin age/age age/age-keygen

SOPS_VERSION=$(curl -s https://api.github.com/repos/getsops/sops/releases/latest | grep tag_name | cut -d'"' -f4)
curl -Lo /usr/local/bin/sops "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.amd64"
chmod +x /usr/local/bin/sops

# Verify both are actually static (should say "statically linked", not "dynamically linked"):
file /usr/local/bin/age /usr/local/bin/sops
```

### Generate your age key and configure the repo

```bash
./scripts/age-setup.sh
```

This script:
1. Generates `~/.config/sops/age/keys.txt` (your keypair)
2. Replaces `AGE_PUBLIC_KEY_PLACEHOLDER` in `.sops.yaml` with your real public key
3. Tells you what to back up

The output looks like:
```
→ Generating new age keypair...
✓ Keypair generated at: /Users/you/.config/sops/age/keys.txt
  Public key: age1qyq2gd3e...

→ Patching .sops.yaml with your public key...
✓ .sops.yaml updated

  Commit .sops.yaml — the public key is safe to store in Git:
    git add .sops.yaml
    git commit -m 'chore: configure sops age public key'

════════════════════════════════════════════════════════════════
  IMPORTANT: Back up your private key to Vaultwarden NOW
════════════════════════════════════════════════════════════════
```

### Back up the private key

```bash
# View your private key
cat ~/.config/sops/age/keys.txt

# It looks like:
# created: 2026-05-19T...
# public key: age1qyq2gd3e...
AGE-SECRET-KEY-1ABCDEF...
```

Copy the entire contents to a Vaultwarden secure note named something like `homelab / sops-age-key / docker-host`. This is the only recovery path if the machine is lost.

---

## Deploying from Semaphore (no manual SSH)

`ansible/playbooks/docker/sops-deploy/` decrypts a service's `.env.sops` **on the
controller** (Athena, wherever Semaphore/Ansible actually run) and deploys it to a
target host over SSH — equivalent of `sops-run.sh <service> up -d`, but triggered
from Semaphore's UI instead of a manual shell session. See that playbook's own
README for usage.

**The age private key exists in two places on Athena**, both required, kept in sync
by hand:

| Path | Used by |
|---|---|
| `~/.config/sops/age/keys.txt` | You, running `scripts/*.sh` by hand from your own shell |
| `/etc/sops/age/keys.txt` | Mounted into the Semaphore container for `sops-deploy` |

Why two copies instead of one: `~/.config` lives under `$HOME`, which is `chmod 750`
— any UID besides `hughboi` (or a member of the `hughboi` group) can't even
traverse into it, regardless of the key file's own permissions. Semaphore's
container runs as a different UID (`1001`, image-specific — see
`apps/docker/semaphore/README.md`), so it needs the key somewhere world-traversable.
`/etc/sops/age/` is `755`; the key file itself stays restricted (`640`, owned
`hughboi:root` — `root`/GID `0` because that's what Semaphore's container actually
runs as, not a made-up group).

**If you ever rotate the age key, update both copies** — nothing currently
automates keeping them in sync. Small, deliberate tradeoff: key rotation is rare
enough that building sync automation for it isn't worth the complexity right now.

```bash
# After generating a new key (age-setup.sh writes to ~/.config/sops/age/keys.txt):
sudo cp ~/.config/sops/age/keys.txt /etc/sops/age/keys.txt
sudo chown hughboi:root /etc/sops/age/keys.txt
sudo chmod 640 /etc/sops/age/keys.txt
cd apps/docker/semaphore && sudo -E ../../../scripts/sops-run.sh semaphore up -d  # picks up the new key on next task run
```

---

## Day-to-day workflow

### Check migration status

```bash
./scripts/sops-check.sh
```

Example output (illustrative — run the script for your actual current counts):
```
SOPS Migration Status  (18 / 36 migrated)
═══════════════════════════════════════════════

Encrypted (.env.sops exists):
  ✓  vaultwarden
  ✓  gitea
  ✓  restic

Not yet migrated (.env.sops missing):
  ✗  homepage
  ✗  immich/home
  ...

  To migrate:  ./scripts/sops-migrate.sh <service>
```

### Deploy a service

```bash
# Replaces: docker compose -f apps/docker/vaultwarden/compose.yaml up -d
./scripts/sops-run.sh vaultwarden up -d

# All docker compose subcommands work:
./scripts/sops-run.sh vaultwarden down
./scripts/sops-run.sh vaultwarden pull
./scripts/sops-run.sh vaultwarden ps
./scripts/sops-run.sh vaultwarden logs -f
./scripts/sops-run.sh vaultwarden restart

# Dry run — see the resolved compose file with vars substituted:
./scripts/sops-run.sh vaultwarden config
```

> [!IMPORTANT] Use `sudo -E`, not plain `sudo`, if the Docker commands need root
> `sops-run.sh` decrypts and exports the secrets into its *own* shell's environment before
> calling `docker compose`. Plain `sudo` starts a fresh environment and loses everything the
> script just exported — Compose falls back to empty values. `-E` preserves the environment
> across the privilege escalation:
>
> ```bash
> sudo -E ./scripts/sops-run.sh semaphore up -d
> ```

---

## Migrating a service

### Prerequisites

Your live `.env` file must exist on disk (it's running right now, so it does).

### Migrate one service

```bash
./scripts/sops-migrate.sh vaultwarden
```

What the script does:
1. Reads `apps/docker/vaultwarden/.env`
2. Strips inline comments (`TOKEN=abc123  # copy from here` → `TOKEN=abc123`)
3. Encrypts all values with your age public key
4. Writes `apps/docker/vaultwarden/.env.sops`
5. Decrypts and verifies: prints variable count
6. Compares keys against `.env.example`: warns if any are missing

Sample output:
```
→ Encrypting vaultwarden/.env → vaultwarden/.env.sops ...
✓ Created: apps/docker/vaultwarden/.env.sops

  Verified: 9 variable(s) decrypt successfully.
  Key coverage: all .env.example keys are present ✓

Next steps:
  1. Test it:    ./scripts/sops-run.sh vaultwarden config
  2. Commit it:  git add apps/docker/vaultwarden/.env.sops
```

### Test before committing

```bash
# This decrypts in memory and shows the fully-resolved compose YAML
# with all ${VAR} substitutions applied — no file written to disk
./scripts/sops-run.sh vaultwarden config
```

If you see your values properly substituted (not empty `${}` blanks), it's working.

### Commit

```bash
git add apps/docker/vaultwarden/.env.sops
git commit -m "chore(vaultwarden): encrypt secrets with sops"
```

### Migrate nested services (Immich has two profiles)

```bash
./scripts/sops-migrate.sh immich/home
./scripts/sops-migrate.sh immich/eros
```

### Migrate all at once

Once all `.env` files are filled in on the current host:

```bash
for svc in paperless-ngx gitea traefik home-assistant hoarder mealie n8n mailrise \
           gatus searxng semaphore romm restic immich/home immich/eros; do
  ./scripts/sops-migrate.sh "$svc"
done
```

---

## Editing secrets

### Change a value in an existing .env.sops

```bash
# Opens .env.sops in $EDITOR (default: vi), decrypted.
# Saves and re-encrypts automatically on exit.
sops apps/docker/vaultwarden/.env.sops
```

You edit a plain text file. On `:wq`, SOPS re-encrypts and writes the updated `.env.sops`. It's the same experience as editing a normal file.

After editing:
```bash
git add apps/docker/vaultwarden/.env.sops
git commit -m "chore(vaultwarden): rotate smtp password"
```

### View current values without editing

```bash
sops --decrypt apps/docker/vaultwarden/.env.sops
```

Or just the value of one key:
```bash
sops --decrypt apps/docker/vaultwarden/.env.sops | grep ADMIN_TOKEN
```

### Update a single key non-interactively

```bash
# Set a key to a new value without opening $EDITOR
sops --set '["ADMIN_TOKEN"] "newvalue"' apps/docker/vaultwarden/.env.sops
```

---

## Rebuilding from scratch

Complete rebuild flow on a new or wiped Docker host:

```bash
# 1. Clone the repo
git clone https://gitea.hughboi.cc/hughboi/homelab.git
cd homelab

# 2. Install tools
brew install sops age    # macOS
# or: apt install age && <download sops binary>

# 3. Restore your private key from Vaultwarden
mkdir -p ~/.config/sops/age
# Paste the private key from Vaultwarden:
nano ~/.config/sops/age/keys.txt
# Paste contents, save.
chmod 600 ~/.config/sops/age/keys.txt

# 4. Verify decryption works
sops --decrypt apps/docker/vaultwarden/.env.sops

# 5. Start deploying
./scripts/sops-run.sh traefik up -d
./scripts/sops-run.sh vaultwarden up -d
./scripts/sops-run.sh gitea up -d
# ... etc

# Or deploy everything:
for svc in traefik adguard vaultwarden gitea paperless-ngx immich/home; do
  ./scripts/sops-run.sh "$svc" up -d
done
```

Time from clone to running: ~5 minutes, zero manual secret-filling.

---

## Multiple machines

### Allowing a second machine to decrypt

SOPS supports multiple age keys as recipients. Both keys can decrypt the same files.

```bash
# Step 1: Run age-setup.sh on the new machine to get its public key
./scripts/age-setup.sh
# Note the public key it prints: age1xxxxx...

# Step 2: On a machine that CAN decrypt, edit .sops.yaml:
# Change:
#   age: age1original...
# To:
#   age: age1original...,age1newmachine...

# Step 3: Re-encrypt all .env.sops files so they include the new key:
find apps/docker -name ".env.sops" -exec sops updatekeys {} \;

# Step 4: Commit .sops.yaml
git add .sops.yaml
git commit -m "chore: add second machine age key"
```

Now both machines can decrypt independently.

### Revoking a machine's access

Remove its public key from `.sops.yaml`, then rotate all encrypted files:

```bash
# Remove the key from .sops.yaml, then:
find apps/docker -name ".env.sops" -exec sops updatekeys {} \;
git add -A
git commit -m "chore: revoke access for old machine"
```

The removed machine's private key can no longer decrypt new `.env.sops` files after this commit.

---

## Key rotation and recovery

### If your private key is compromised

```bash
# 1. Generate a new keypair (overwrites the old key on disk)
age-keygen -o ~/.config/sops/age/keys.txt

# 2. Get the new public key
NEW_KEY=$(grep "# public key:" ~/.config/sops/age/keys.txt | awk '{print $NF}')
echo "New public key: $NEW_KEY"

# 3. Update .sops.yaml with the new public key (replace the old one)
# Edit .sops.yaml manually or use sed:
sed -i "s|age: age1.*|age: $NEW_KEY|" .sops.yaml

# 4. Re-encrypt all files.
# NOTE: You need the OLD private key to decrypt. If you no longer have it, see below.
# If you still have it on another machine, run updatekeys from there:
find apps/docker -name ".env.sops" -exec sops updatekeys {} \;

# 5. Back up the new private key to Vaultwarden, remove the old one
# 6. Commit .sops.yaml
git add .sops.yaml && git commit -m "chore: rotate sops age key"
```

### If you've lost the private key entirely

If both the on-disk key AND the Vaultwarden backup are gone: the `.env.sops` files cannot be decrypted. Recovery means:

1. Pull values from the running containers' environment:
   ```bash
   docker inspect <container> | jq '.[0].Config.Env'
   ```
2. Re-create the `.env` files from the running state
3. Generate a new age key: `./scripts/age-setup.sh`
4. Re-migrate each service: `./scripts/sops-migrate.sh <service>`

This is why the Vaultwarden backup is non-negotiable.

---

## How the CI check works

The `.gitea/workflows/ci.yaml` pipeline includes a `sops-coverage` job that runs on every push/PR. It:

1. Finds every `apps/docker/**/.env.example` in the repo
2. For each one, checks that a `.env.sops` file exists alongside it
3. Extracts key names from `.env.sops` (SOPS keeps keys readable) and compares them to `.env.example`
4. Fails the build if any service is missing `.env.sops` OR if any key from `.env.example` is absent in `.env.sops`

**No decryption happens in CI.** The age private key is never in CI. The check only validates structure (key names), not values.

This means: adding a new secret to `.env.example` without updating `.env.sops` will break the CI check, reminding you to re-encrypt.

---

## Troubleshooting

### `failed to get the data key: no key could decrypt`

Your age private key is missing or wrong.

```bash
# Check it exists
ls -la ~/.config/sops/age/keys.txt

# Check the public key matches what's in .sops.yaml
grep "public key" ~/.config/sops/age/keys.txt
grep "age:" .sops.yaml
# Both should show the same public key
```

If missing: restore from Vaultwarden.

### `Error: SOPS_AGE_KEY_FILE is not set` or similar

SOPS looks for the key at `~/.config/sops/age/keys.txt` by default. If yours is elsewhere:

```bash
export SOPS_AGE_KEY_FILE=/path/to/your/keys.txt
./scripts/sops-run.sh vaultwarden up -d
```

### `mac mismatch` or `mac verify failed`

The encrypted file was corrupted or manually edited (never edit `.env.sops` in a text editor — always use `sops <file>`).

```bash
# Check if the file is intact
sops --decrypt apps/docker/<service>/.env.sops

# If it fails, restore from Git
git checkout apps/docker/<service>/.env.sops
```

### Services not getting their env vars after migration

```bash
# See exactly what compose would receive (dry run, no containers started)
./scripts/sops-run.sh <service> config

# Look for any ${VAR} that appears unsubstituted (shows as empty or literal ${VAR})
# If a var is missing from .env.sops, add it with sops <file>
```

### `sops-run.sh` falls back to the `.env` file on disk

The service hasn't been migrated yet.

```bash
./scripts/sops-migrate.sh <service>
```

### `sops-run.sh` exits silently with no output, no error

Almost certainly a `.env` with `UID=` in it (common Docker pattern for matching a container's
user to the host's). `UID`/`EUID` are readonly bash built-ins — `sops-run.sh` skips them by
design (the script's own `$UID` already equals the real value, so nothing is lost), but if
you're troubleshooting a *modified* copy of the script, know that a failed `export` of a
readonly name under `set -e` aborts silently — a trailing `|| ...` fallback does **not**
reliably catch it in this context, tested and confirmed against bash. The name has to be
checked and skipped *before* attempting the export, not caught after.

### A key exists in `.env.sops` but with an empty value

When you migrated, the `.env` file had `KEY=` with nothing after the `=`. Fix it:

```bash
# Open .env.sops in editor, set the value
sops apps/docker/<service>/.env.sops
# Find the KEY= line, add the value, save
git add apps/docker/<service>/.env.sops
git commit -m "chore(<service>): fill in missing secret value"
```

---

## Cheatsheet

```bash
# ── Setup ────────────────────────────────────────────────────────────────────
./scripts/age-setup.sh                        # generate key, patch .sops.yaml
cat ~/.config/sops/age/keys.txt               # view private key (back up to Vaultwarden)

# ── Migration ─────────────────────────────────────────────────────────────────
./scripts/sops-check.sh                       # show which services still need migration
./scripts/sops-migrate.sh vaultwarden         # encrypt one service's .env → .env.sops
./scripts/sops-migrate.sh immich/home         # nested path

# ── Deploy ────────────────────────────────────────────────────────────────────
./scripts/sops-run.sh vaultwarden up -d       # bring up (secrets injected in memory)
./scripts/sops-run.sh vaultwarden down        # bring down
./scripts/sops-run.sh vaultwarden pull        # pull latest images
./scripts/sops-run.sh vaultwarden config      # dry run: see resolved compose YAML
./scripts/sops-run.sh vaultwarden logs -f     # tail logs

# ── Edit secrets ──────────────────────────────────────────────────────────────
sops apps/docker/vaultwarden/.env.sops        # open in $EDITOR, auto re-encrypts on save
sops --decrypt apps/docker/vaultwarden/.env.sops            # print decrypted to stdout
sops --decrypt apps/docker/vaultwarden/.env.sops | grep KEY # grep a specific key
sops --set '["KEY"] "newvalue"' apps/docker/vaultwarden/.env.sops  # set without editor

# ── Multiple machines ─────────────────────────────────────────────────────────
# Add a new machine's public key to .sops.yaml, then:
find apps/docker -name ".env.sops" -exec sops updatekeys {} \;

# ── Recovery ──────────────────────────────────────────────────────────────────
# Restore private key from Vaultwarden:
mkdir -p ~/.config/sops/age && nano ~/.config/sops/age/keys.txt && chmod 600 $_
# Verify:
sops --decrypt apps/docker/vaultwarden/.env.sops
```

---

## Reference

| File/Path | Purpose |
|-----------|---------|
| `.sops.yaml` | Encryption config — which files, which key |
| `scripts/age-setup.sh` | One-time key generation + `.sops.yaml` wiring |
| `scripts/sops-migrate.sh` | Encrypt a live `.env` → `.env.sops` |
| `scripts/sops-run.sh` | Run docker compose with memory-only secret injection |
| `scripts/sops-check.sh` | Migration progress dashboard |
| `~/.config/sops/age/keys.txt` | Age private key (back up to Vaultwarden) |
| `apps/docker/<svc>/.env.sops` | Encrypted secrets for each service (in Git) |
| `apps/docker/<svc>/.env` | Plaintext secrets on disk (gitignored, still needed for first migration) |
| `.gitea/workflows/ci.yaml` | CI job: validates .env.sops key coverage |
