# Vaultwarden

**URL:** https://vaultwarden.hughboi.cc/setup

---

## Secrets (SOPS)

`.env` (`.env.sops`) — `DOMAIN`, `ADMIN_TOKEN` (already an argon2id hash, not a raw token — see
Admin Panel section below for how it's generated), and the 6 `SMTP_*` fields. `.env.example` also
lists 5 `OIDC_*` fields, but they are **not currently set** in production — OIDC/PocketID login is
configured as documented below but not active via env vars right now; don't assume it's live
without checking `docker inspect vaultwarden --format '{{json .Config.Env}}'` first.

---

# Security

## 2FA

1. In the web app, go to Settings → Security.
2. Select Two-step login.
3. Under Passkey, hit Manage.
   - Add a name (e.g. `Yubikey - 1`)
   - Register at least two keys — ideally both YubiKeys.

## Device Sign In

After signing in on a primary device (app or browser), a second device can sign in without the
master password:

1. Enter email, then select **Login with device** instead of entering your master password.
2. On your already-logged-in session, go to Settings → Account Security → Pending Login Requests
   and approve.

> **Note:** Device sign in only bypasses the first factor. If 2FA is enabled, you will still need
> your 2FA token or passkey.

## Passkey Sign On (Bitwarden only!)

> **Note:** Single-factor passkey login is not yet implemented in Vaultwarden. This section
> applies to Bitwarden accounts. Check your running version (`1.35.7`) for current passkey support
> status. Bitwarden accounts support up to five passkeys per account.

To create a passkey for login:

1. In the web app, go to Settings → Security → Master password.
2. Under **Log in with passkey**, select **Turn on** (or **New passkey** if one already exists).
   You will be prompted for your master password.
3. Follow your browser's prompts to create a FIDO2 passkey using a biometric or PIN.
4. Enter a name for the passkey.
5. If your browser and authenticator are PRF-capable, **Use for vault encryption** will be checked
   by default — this allows the passkey to decrypt and unlock your vault. Uncheck if you do not
   want this behaviour.

To log in with a passkey:

1. On the login screen, select **Log in with passkey**.
2. Follow your browser's prompts to read the passkey.
3. If the passkey is set up for vault encryption, you are done — the vault will decrypt
   automatically. Otherwise, enter your master password or use another configured unlock method.

To unlock an already-logged-in vault, select **Unlock with Passkey** on the locked vault screen and
follow your browser's prompts.

## Recovery Keys

Obtain via: Settings → Security → Two-step Login → View Recovery Code.

Store in at least three places:

1. Physical copy in a safe
2. Encrypted file on TrueNAS
3. iCloud Keychain
4. Paperless-ngx
5. *(Optional)* Emergency contact with a second email address — create the user first, then go to
   Settings → Emergency Access → Add emergency contact (Access Level: View or Takeover)

---

# Admin Panel

> **Note:** Everything here can be configured via environment variables. The GUI is only needed if
> you prefer it.

## Enabling the Panel

1. Set `ADMIN_TOKEN=` in your environment. Then exec into the container and run:
   ```sh
   /vaultwarden hash
   ```
2. Set a password and copy the resulting hashed string. Remove the surrounding single quotes.
   - If the hash contains any `$` signs, escape each one with another `$` (i.e. `$$`).
   - Check the container logs to confirm the hash is being accepted.
3. Navigate to https://vaultwarden.hughboi.cc/admin

## OpenID SSO

- OpenID Connect SSO Settings:
  - Enabled: checked
  - Configure Client ID, Secret, and Callback URL with PocketID
  - Authorization request scopes: `openid email profile`

> **Warning:** PocketID cannot be linked to an existing Vaultwarden account — it interprets this as
> an account hijacking attempt. Went down this route for many hours before deciding to just wait
> until Vaultwarden officially supports passkeys natively (passkey-native SSO support is pending in
> a future release).

## SMTP

Only needed to change the send address or to support emergency access requests (lets a takeover
requestee email admins).

- Enabled: `true`
- Host: `smtp.fastmail.com`
- Secure SMTP: `starttls`
- Port: `587`
- From: Fastmail address
- Password: Fastmail App Password

---

# Backups

**Official docs:** https://github.com/dani-garcia/vaultwarden/wiki/Backing-up-your-vault

**Current backup strategy:**

1. Proxmox Backup Server — VM image snapshot (1x daily)
2. Restic → TrueNAS (2x daily)
3. Encrypted tar of `/data` (1x daily) — **currently orchestrated via n8n** (see "N8N Backups"
   below); an Ansible/Semaphore version of the same job exists (see "Ansible Backups") and is the
   intended target once the migration off n8n is complete. Treat n8n as authoritative until this
   note is updated.

## Manual Backup

> **Warning:** These ad-hoc commands do not use the safe `sqlite3 .backup` method that the
> automated jobs use. If running manually, stop the container first to avoid a mid-write snapshot.

Stop Vaultwarden:
```sh
docker stop vaultwarden
```

**Unencrypted** — two equivalent variants seen in use:

Variant 1 — tar just the `data` subdirectory directly (no exclude needed):
```sh
tar -czf /home/hughboi/data/vaultwarden/backups/vaultwarden-$(date +%F).tar.gz \
  -C /home/hughboi/data/vaultwarden data
```

Variant 2 — tar the whole Vaultwarden directory, excluding the backups folder itself:
```sh
tar -czf /home/hughboi/data/vaultwarden/backups/vaultwarden-$(date +%F).tar.gz \
  --exclude='./backups' -C /home/hughboi/data/vaultwarden .
```

**Encrypted** — two equivalent variants seen in use:

Variant 1 — public key derived automatically from the private key file:
```sh
DATE=$(TZ="America/Denver" date +%F) \
  && TAR_FILE="/home/hughboi/data/vaultwarden/backups/vaultwarden-$DATE.tar.gz" \
  && ENC_FILE="$TAR_FILE.age" \
  && tar -czf "$TAR_FILE" -C /home/hughboi/data/vaultwarden data \
  && age -r $(age-keygen -y ~/.config/age/keys.txt) -o "$ENC_FILE" "$TAR_FILE" \
  && rm "$TAR_FILE"
```

Variant 2 — public key pasted in manually:
```sh
DATE=$(TZ="America/Denver" date +%F) \
  && TAR_FILE="/home/hughboi/data/vaultwarden/backups/vaultwarden-$DATE.tar.gz" \
  && ENC_FILE="$TAR_FILE.age" \
  && tar -czf "$TAR_FILE" --exclude='./backups' -C /home/hughboi/data/vaultwarden . \
  && age -r YOUR_PUBLIC_KEY_HERE -o "$ENC_FILE" "$TAR_FILE" \
  && rm "$TAR_FILE"
```

### No-Downtime Manual Backup

Take a consistent hot backup without stopping the container:
```sh
docker exec vaultwarden sqlite3 /data/db.sqlite3 ".backup '/data/db-backup.sqlite3'"
```

Then tar up `db-backup.sqlite3` instead of the live `db.sqlite3`.

## Encryption Setup

> Create `~/.config/age/` if it does not exist yet.

1. Install age:
   ```sh
   sudo apt install age
   ```
2. Generate a key:
   ```sh
   age-keygen -o ~/.config/age/keys.txt
   ```
3. Back up the private key to: Vaultwarden, iCloud, TrueNAS, and a printed physical copy.
4. Lock down permissions:
   ```sh
   chmod 600 ~/.config/age/keys.txt
   ```
5. Use your public key with `-r age1xxxxxxx`, or extract it automatically with
   `age-keygen -y ~/.config/age/keys.txt`.

## Docker-Based Automated Backups (Official Example — reference only, not currently in use)

This stops the container to ensure consistency, zips the data directory, transfers it via scp to
another host, and then restarts Vaultwarden. Some of the other methods don't require downtime, so
this isn't suitable for zero-downtime/automated environments and isn't personally used — kept here
for reference.

```bash
#!/bin/bash
docker-compose down
datestamp=$(date +%m-%d-%Y)
backup_dir="/home/hughboi/data/vaultwarden/backups"
zip -9 -r "${backup_dir}/${datestamp}.zip" /home/hughboi/data/vaultwarden/data
scp -i ~/.ssh/id_rsa "${backup_dir}/${datestamp}.zip" hughboi@<10.10.10.5>:~/homelab/vaultwarden/
docker-compose up -d
```

Automate via cron:
```
0 0 * * * /root/transfer_vaultwarden_logs.sh
```

Cleanup script (optional) to keep only the most recent backup:
```bash
#!/bin/bash
cd ~/backups || exit
find . -type f -name '*.zip' ! -mtime -1 -exec rm {} +
```

To restore: unzip the archive back into `/data`, replacing the previous data directory. Always test
restores.

## N8N Backups — currently in use

1. Schedule Trigger (8:00 am daily)
2. Execute command
   - Credentials to connect with (SSH Password account)
   - Resource: Command
   - Operation: Execute
   - Command (backs up sqlite database + data folder, zips it, encrypts it, puts into local
     backups, purges anything over 45 days, calculates backup size):
   ```sh
   sqlite3 /home/hughboi/data/vaultwarden/data/db.sqlite3 ".backup /home/hughboi/data/vaultwarden/data/db-backup.sqlite3" && sync && BACKUP_DIR="/home/hughboi/data/vaultwarden/backups" && mkdir -p "$BACKUP_DIR" && DATE=$(TZ="America/Denver" date +%F) && TAR_FILE="$BACKUP_DIR/vaultwarden-$DATE.tar.gz" && ENC_FILE="$TAR_FILE.age" && tar --warning=no-file-changed -czf "$TAR_FILE" -C /home/hughboi/data/vaultwarden data && age -r age15zjkhtmytnx5l6fhhpte6gg5ha9ede28tgwcd2ewxtwth9l5090sve0rv6 -o "$ENC_FILE" "$TAR_FILE" && sha256sum "$ENC_FILE" > "$ENC_FILE.sha256" && rm "$TAR_FILE" && rm /home/hughboi/data/vaultwarden/data/db-backup.sqlite3 && LATEST=$(ls -t "$BACKUP_DIR"/vaultwarden-*.tar.gz.age | head -1) && SIZE=$(du -h "$LATEST" | awk '{print $1}') && PURGED=$(find "$BACKUP_DIR" \( -name "*.tar.gz.age" -o -name "*.tar.gz.age.sha256" \) -type f -mtime +45 -print -delete | tr '\n' ' ') && printf "size=%s purged=%s\n" "$SIZE" "${PURGED:-None}"
   ```
   - Working Directory: `/home/hughboi/`
   - Settings: ALWAYS OUTPUT DATA / On Error (Continue)
3. IF
   - Condition: `{{ $json.code }}` is equal to **0** ← True Route
4. Success Path:
   - HTTP POST to `https://ntfy.hughboi.cc/n8n`
   - Body Content Type: Raw
   - Send Body (checked):
     ```
     Vaultwarden backup completed!
     Date/Time: {{ $now.format('yyyy-MM-dd HH:mm:ss') }}
     Content: {{ $json.stdout }}
     ```
5. Failure Path:
   - Body:
     ```
     Vaultwarden Backup FAILURE - {{ $now.format('yyyy-MM-dd HH:mm:ss') }}
     Error: {{ $json.stderr }}
     ```

## Ansible Backups — migration target (not yet authoritative)

Intended to run daily via Ansible playbook scheduled through Semaphore, doing the same job as the
N8N workflow above. The playbook:

- Checkpoints the WAL before backup
- Takes a consistent SQLite hot backup via `.backup`
- Creates an encrypted age archive with a SHA256 checksum
- Purges backups older than 45 days
- Sends a success/failure notification via ntfy

## Testing Restores with n8n — currently in use

- Node 1 — Schedule
  - 1x month
- Node 2 — SSH
  - Find latest backup
  ```sh
  ls -t /home/hughboi/data/vaultwarden/backups/*.tar.gz.age | head -1
  ```
- Node 3 — Code (JavaScript)
  - Data modification (Raw → Structured)
  ```js
  return [{
    json: {
      ...$json,
      backup: $json.stdout.trim()
    }
  }];
  ```
- Node 4 — SSH
  - Decrypt backup (Expression):
  ```sh
  BACKUP="{{ $json.backup }}"
  BACKUP_DIR=$(dirname "$BACKUP")
  BACKUP_FILE=$(basename "$BACKUP")
  TMP=$(mktemp -d)

  # 1. Change to the directory so sha256sum finds the file correctly
  cd "$BACKUP_DIR"

  # 2. Verify Checksum
  if ! sha256sum -c "$BACKUP_FILE.sha256" > /dev/null 2>&1; then
      printf '{"status":"fail","error":"checksum_mismatch","backup":"%s"}' "$BACKUP"
      exit 0
  fi

  # 3. Decrypt
  if age -d -i ~/.config/age/keys.txt "$BACKUP_FILE" > "$TMP/vw.tar.gz" 2>/dev/null; then
      printf '{"status":"ok","backup":"%s","tmp":"%s"}' "$BACKUP" "$TMP"
  else
      printf '{"status":"fail","error":"decryption_failed","backup":"%s"}' "$BACKUP"
  fi
  ```
- Node 5 — Code (JavaScript)
  - JSON parse → object:
  ```js
  const data = JSON.parse($json.stdout);

  return [{
    json: {
      backup: data.backup,
      tmp: data.tmp.replace("tmp:", "")
    }
  }];
  ```
- Node 6 — SSH
  - Extract backup (Expression):
  ```sh
  TMP="{{ $json.tmp }}" && tar -xzf "$TMP/vw.tar.gz" -C "$TMP" && printf "$TMP"
  ```
- Node 7 — Code (JavaScript)
  ```js
  for (const item of $input.all()) {
    item.json.myNewField = 1;
  }

  return $input.all();
  ```
- Node 8 — SSH
  - Start vaultwarden test container (Expression):
  ```sh
  # 1. Setup path
  TMP=$(echo "{{ $json.stdout }}" | head -n 1 | tr -d '"')

  # 2. Start container and WAIT for it to be ready
  docker run -d --rm --name vw-test -p 8093:80 -v "$TMP/data:/data" vaultwarden/server:latest > /dev/null
  until curl -sf http://localhost:8093/alive > /dev/null; do sleep 1; done

  # 3. RUN THE CHECKS while it is still running
  STATUS="ok"
  ERROR=""
  if ! curl -sf http://localhost:8093/api/config > /dev/null; then
      ERROR="api_failed"
  elif ! (sqlite3 "$TMP/data/db.sqlite3" "PRAGMA integrity_check;" || sqlite3 "$TMP/db.sqlite3" "PRAGMA integrity_check;") | grep -q "ok"; then
      ERROR="sqlite_failed"
  fi

  # 4. NOW TEARDOWN (Only after checks are done)
  [ -n "$ERROR" ] && STATUS="fail"
  docker stop vw-test > /dev/null || true

  # 5. Output the result to n8n
  printf '{"status":"%s","error":"%s","backup":"%s"}\n' "$STATUS" "$ERROR" "{{ $('Extract Path').item.json.backup }}"
  ```
- Node 9 — IF
  ```
  {{ JSON.parse($('Start Test Container').item.json.stdout).status }} == ok
  ```
  - Success: POST to `https://ntfy.hughboi.cc/n8n`, raw body:
    `Vaultwarden Restore Test PASSED | Backup={{ $json.backup }} | Time={{ $now }}`
  - Failure: POST to `https://ntfy.hughboi.cc/n8n`, raw body:
    `Vaultwarden Restore Test FAILED | Error={{ $json.error }} | Backup={{ $json.backup }} | Time={{ $now }}`

## Weekly Backup Validation — Ansible migration target (not yet authoritative)

Intended to run weekly via Ansible playbook scheduled through Semaphore, doing the same job as
"Testing Restores with n8n" above but on a weekly instead of monthly cadence, and against a pinned
image instead of `:latest`. The playbook:

- Finds the most recent encrypted backup
- Verifies its SHA256 checksum
- Decrypts and extracts the archive
- Promotes `db-backup.sqlite3` over `db.sqlite3` (mirroring the real restore procedure)
- Spins up a test Vaultwarden container (`vaultwarden/server:1.35.7`, pinned to match production)
  against the restored data
- Verifies the `/alive` and `/api/config` endpoints respond
- Runs `PRAGMA integrity_check` on the restored database
- Sends a success/failure notification via ntfy

---

# Restores

> Always test restores before you need them.

🚨 **Critical steps for any restore:**
1. Stop the container before touching any files.
2. Run `PRAGMA integrity_check;` on the restored DB — if the result is anything other than `ok`, do
   not proceed.
3. Run `chown -R 1000:1000` on the data directory — the container will fail to write without
   correct ownership.
4. Remove `.wal` and `.shm` files when wiping a corrupted data directory — leaving them causes
   corruption.

## Manual Restore

1. Stop Vaultwarden:
   ```sh
   docker stop vaultwarden
   ```

2. Preserve the broken data directory and create a fresh one:
   ```sh
   mv /home/hughboi/data/vaultwarden/data /home/hughboi/data/vaultwarden/data.broken.$(date +%F)
   mkdir -p /home/hughboi/data/vaultwarden/data
   ```

3. Decrypt the backup (cd into the backups directory first; point `-i` at your actual key file
   location):
   ```sh
   age -d -i ~/.config/age/keys.txt vaultwarden-YYYY-MM-DD.tar.gz.age > vaultwarden.tar.gz
   ```

4. Extract the archive:
   ```sh
   tar -xzf vaultwarden-YYYY-MM-DD.tar.gz -C /home/hughboi/data/vaultwarden
   ```

5. Promote the hot backup as the canonical database. The archive contains both `db.sqlite3` (live
   at backup time, may have been mid-write) and `db-backup.sqlite3` (clean consistent snapshot).
   **Always use the hot backup:**
   ```sh
   mv /home/hughboi/data/vaultwarden/data/db-backup.sqlite3 \
      /home/hughboi/data/vaultwarden/data/db.sqlite3
   ```

6. Set permissions if needed:
   ```sh
   chown -R 1000:1000 /home/hughboi/data/vaultwarden/data
   ```

7. Start Vaultwarden:
   ```sh
   docker start vaultwarden
   ```

## Restic Restore

1. List snapshots:
   ```sh
   docker exec -it restic restic snapshots
   ```

2. Restore a specific snapshot:
   ```sh
   # Replace SNAPSHOT_ID with your actual ID (e.g. 36aa3445)
   docker exec -it restic restic restore SNAPSHOT_ID \
     --target /tmp-for-restore \
     --include /mnt/volumes/data/vaultwarden/data/db.sqlite3
   ```
   > Restic ignores `lchown` errors on NFS mounts — as long as the output says
   > `Summary: Restored 1 files`, it worked.

3. Run an integrity check:
   ```sh
   sqlite3 /mnt/truenas/restic/tmp-for-restore/mnt/volumes/data/vaultwarden/data/db.sqlite3 \
     "PRAGMA integrity_check;"
   ```
   > If the output is anything other than `ok`, stop. Delete the temp file and repeat from step 2
   > with an older snapshot.

4. Wipe the corrupted directory and replace it:
   ```sh
   docker stop vaultwarden

   # Remove ALL files including .wal and .shm
   rm -rf /home/hughboi/data/vaultwarden/data/*

   # Move the verified DB into place
   cp /mnt/truenas/restic/tmp-for-restore/mnt/volumes/data/vaultwarden/data/db.sqlite3 \
     /home/hughboi/data/vaultwarden/data/

   # Restore config if present
   [ -f /mnt/truenas/restic/tmp-for-restore/mnt/volumes/data/vaultwarden/data/config.json ] \
     && cp /mnt/truenas/restic/tmp-for-restore/mnt/volumes/data/vaultwarden/data/config.json \
          /home/hughboi/data/vaultwarden/data/
   ```

5. Fix ownership and restart:
   ```sh
   chown -R 1000:1000 /home/hughboi/data/vaultwarden/data
   docker start vaultwarden
   ```

---

# Other

- A SQLite `VACUUM` is run once a year for database health maintenance, orchestrated via Ansible
  and Semaphore.
- SQLite is best kept as a host file on the system for easy backups, but databases like Postgres
  are better off as a docker volume — better performance, and you'd back those up with `pg_dump`
  anyway.