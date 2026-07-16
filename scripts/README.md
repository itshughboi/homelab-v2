# Scripts

Secrets management tooling for the Docker stack. All scripts use [SOPS](https://github.com/getsops/sops) with [age](https://github.com/FiloSottile/age) encryption to store `.env` secrets safely in Git.

---

## Why SOPS + age

Docker Compose services need `.env` files with real credentials. These can't be committed to Git in plaintext. SOPS encrypts the values (not the keys) with your age public key — the encrypted `.env.sops` file is safe to commit; only someone with the private key can decrypt it.

---

## Scripts

### `age-setup.sh` — one-time setup per machine

Run this once on any machine that needs to encrypt or decrypt secrets:

```bash
./scripts/age-setup.sh
```

What it does:
1. Generates an age keypair at `~/.config/sops/age/keys.txt`
2. Patches `.sops.yaml` in the repo root with your public key
3. Reminds you to back up the private key to Vaultwarden

**Run this first.** All other scripts depend on the key being in place.

---

### `sops-migrate.sh` — encrypt a service's `.env`

Encrypts a live `.env` file into a `.env.sops` file that's safe to commit:

```bash
./scripts/sops-migrate.sh <service>

# Examples:
./scripts/sops-migrate.sh vaultwarden
./scripts/sops-migrate.sh immich/home
```

What it does:
1. Reads `apps/docker/<service>/.env` (must exist on this machine with real values)
2. Strips inline comments from values (avoids encrypting them as part of the value)
3. Encrypts with SOPS → writes `apps/docker/<service>/.env.sops`
4. Verifies the result decrypts cleanly
5. Checks key coverage against `.env.example` and warns about any missing keys

**Prerequisite:** `.env` must exist and be populated. Copy from `.env.example` and fill in values first.

---

### Editing an existing secret (already-encrypted `.env.sops`)

Don't manually decrypt-edit-re-encrypt — `sops` has a built-in edit mode that does it in one
step, with no intermediate plaintext file ever touching disk:

```bash
sops apps/docker/<service>/.env.sops
```

This opens the decrypted contents in `$EDITOR` (a temp file, not the real `.env`), and
re-encrypts automatically on save/exit. If `$EDITOR` isn't set, `sops` falls back to `vi`. Only
works on a machine with the private age key available (e.g. Athena).

To just view a decrypted value without editing:

```bash
sops --decrypt apps/docker/<service>/.env.sops
```

---

### `sops-run.sh` — start a service with secrets injected

Decrypts `.env.sops` in memory and runs Docker Compose without writing plaintext to disk:

```bash
./scripts/sops-run.sh <service> [docker compose args...]

# Examples:
./scripts/sops-run.sh vaultwarden up -d
./scripts/sops-run.sh vaultwarden down
./scripts/sops-run.sh vaultwarden pull
./scripts/sops-run.sh vaultwarden config    # dry-run: print resolved compose file
./scripts/sops-run.sh immich/home up -d
```

Falls back to plain `docker compose` if no `.env.sops` exists (for services with no secrets).

---

### `sops-check.sh` — audit migration status

Shows which services have been migrated to SOPS and which haven't:

```bash
./scripts/sops-check.sh
```

Output:
```
SOPS Migration Status  (12 / 15 migrated)
═══════════════════════════════════════════

Encrypted (.env.sops exists):
  ✓  vaultwarden
  ✓  gitea
  ⚠  paperless-ngx  (missing keys: PAPERLESS_SECRET_KEY)
  ...

Not yet migrated (.env.sops missing):
  ✗  some-service
  ...
```

Run this after a rebuild to see what still needs to be set up.

---

## First-time setup on a new machine

```bash
# 1. Generate your age key
./scripts/age-setup.sh

# 2. Restore your private key from Vaultwarden into:
#    ~/.config/sops/age/keys.txt
#    (the file age-setup.sh just created will be overwritten with the real key)

# 3. Verify you can decrypt
./scripts/sops-run.sh vaultwarden config
```

If you're setting up a completely fresh machine (no existing key in Vaultwarden), just run `age-setup.sh` — it generates a new key and gives you the backup reminder.

---

## Full workflow for a new service

```bash
# 1. Create the .env file with real values
cp apps/docker/myservice/.env.example apps/docker/myservice/.env
$EDITOR apps/docker/myservice/.env

# 2. Encrypt it
./scripts/sops-migrate.sh myservice

# 3. Test decryption
./scripts/sops-run.sh myservice config

# 4. Commit the encrypted file (NOT the plaintext .env)
git add apps/docker/myservice/.env.sops
git commit -m "chore: encrypt myservice secrets"

# 5. Delete the plaintext .env (it's no longer needed for deployments)
rm apps/docker/myservice/.env
```

---

## Key management

| File | Location | Commit to Git? |
|------|----------|----------------|
| age public key | `.sops.yaml` (in repo) | Yes |
| age private key (for running scripts by hand) | `~/.config/sops/age/keys.txt` | **Never** |
| age private key (for Semaphore's `sops-deploy` playbook) | `/etc/sops/age/keys.txt` — a separate copy, see below | **Never** |
| Backup of private key | Vaultwarden secure note | Stored in Vaultwarden |
| `.env.sops` files | `apps/docker/<service>/` | Yes |
| `.env` files (plaintext) | `apps/docker/<service>/` | **Never** (in `.gitignore`) |

If the private key is ever lost, the `.env.sops` files become permanently unreadable — there is no recovery path. Keep the Vaultwarden backup current.

**Why the key exists in two places on Athena:** `~/.config` lives under `$HOME`, which is
`chmod 750` — Semaphore's container runs as a different UID (image-specific, not your host
user) and can't traverse into `$HOME` at all, regardless of the key file's own permissions.
`/etc/sops/age/` is world-traversable (`755`) with the key itself still restricted (`640`,
`hughboi:root`). **Not kept in sync automatically** — if you rotate the key, update both copies.
See "Deploying from Semaphore" in [docs/8-gitops/sops-secrets.md](../docs/8-gitops/sops-secrets.md).
