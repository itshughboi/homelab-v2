# Vaultwarden

**URL:** https://vaultwarden.hughboi.cc/setup

---

# Security

## 2FA

1. In the web app, go to Settings → Security.
2. Select Two-step login.
3. Under Passkey, hit Manage.
   - Add a name (e.g. `Yubikey - 1`)
   - Register at least two keys — ideally both YubiKeys.

## Device Sign In

After signing in on a primary device, a second device can sign in without the master password:

1. Enter email, then select **Login with device** instead of entering your master password.
2. On your already-logged-in session, go to Settings → Account Security → Pending Login Requests and approve.

> **Note:** Device sign in only bypasses the first factor. If 2FA is enabled, you will still need your 2FA token or passkey.

## Passkey Sign On

> **Note:** Single-factor passkey login is not yet implemented in Vaultwarden. This section applies to Bitwarden accounts. Check your running version (`1.35.7`) for current passkey support status.

To create a passkey for login:

1. In the web app, go to Settings → Security → Master password.
2. Under **Log in with passkey**, select **Turn on** (or **New passkey** if one already exists). You will be prompted for your master password.
3. Follow your browser's prompts to create a FIDO2 passkey using a biometric or PIN.
4. Enter a name for the passkey.
5. If your browser and authenticator are PRF-capable, **Use for vault encryption** will be checked by default — this allows the passkey to decrypt and unlock your vault. Uncheck if you do not want this behaviour.

To log in with a passkey:

1. On the login screen, select **Log in with passkey**.
2. Follow your browser's prompts to read the passkey.
3. If the passkey is set up for vault encryption, you are done — the vault will decrypt automatically. Otherwise, enter your master password or use another configured unlock method.

To unlock an already-logged-in vault, select **Unlock with Passkey** on the locked vault screen and follow your browser's prompts.

## Recovery Keys

Obtain via: Settings → Security → Two-step Login → View Recovery Code.

Store in at least three places:

1. Physical copy in a safe
2. Encrypted file on TrueNAS
3. iCloud Keychain
4. Paperless-ngx
5. *(Optional)* Emergency contact with a second email address — create the user first, then go to Settings → Emergency Access → Add emergency contact (Access Level: View or Takeover)

---

# Admin Panel

> **Note:** Everything here can be configured via environment variables. The GUI is only needed if you prefer it.

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

> **Warning:** PocketID cannot be linked to an existing Vaultwarden account — it interprets this as an account hijacking attempt. Passkey-native SSO support is pending in a future Vaultwarden release.

## SMTP

Only needed to change the send address or to support emergency access requests.

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
3. Encrypted tar of `/data` via Ansible playbook (1x daily)

## Manual Backup

> **Warning:** These commands do not use the safe `sqlite3 .backup` method that the Ansible playbook uses. If running manually, stop the container first to avoid a mid-write snapshot.

Stop Vaultwarden:
```sh
docker stop vaultwarden
```

Unencrypted:
```sh
tar -czf /home/hughboi/data/vaultwarden/backups/vaultwarden-$(date +%F).tar.gz \
  -C /home/hughboi/data/vaultwarden data
```

Encrypted:
```sh
DATE=$(TZ="America/Denver" date +%F) \
  && TAR_FILE="/home/hughboi/data/vaultwarden/backups/vaultwarden-$DATE.tar.gz" \
  && ENC_FILE="$TAR_FILE.age" \
  && tar -czf "$TAR_FILE" -C /home/hughboi/data/vaultwarden data \
  && age -r $(age-keygen -y ~/.config/age/keys.txt) -o "$ENC_FILE" "$TAR_FILE" \
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
5. Use your public key with `-r age1xxxxxxx` or extract it automatically with `age-keygen -y ~/.config/age/keys.txt`.

## Ansible Backups

Runs daily via Ansible playbook scheduled through Semaphore. The playbook:

- Checkpoints the WAL before backup
- Takes a consistent SQLite hot backup via `.backup`
- Creates an encrypted age archive with a SHA256 checksum
- Purges backups older than 45 days
- Sends a success/failure notification via ntfy

## Weekly Backup Validation

Runs weekly via Ansible playbook scheduled through Semaphore. The playbook:

- Finds the most recent encrypted backup
- Verifies its SHA256 checksum
- Decrypts and extracts the archive
- Promotes `db-backup.sqlite3` over `db.sqlite3` (mirroring the real restore procedure)
- Spins up a test Vaultwarden container (`vaultwarden/server:1.35.7`) against the restored data
- Verifies the `/alive` and `/api/config` endpoints respond
- Runs `PRAGMA integrity_check` on the restored database
- Sends a success/failure notification via ntfy

---

# Restores

> Always test restores before you need them.

🚨 **Critical steps for any restore:**
1. Stop the container before touching any files.
2. Run `PRAGMA integrity_check;` on the restored DB — if the result is anything other than `ok`, do not proceed.
3. Run `chown -R 1000:1000` on the data directory — the container will fail to write without correct ownership.
4. Remove `.wal` and `.shm` files when wiping a corrupted data directory — leaving them causes corruption.

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

3. Decrypt the backup (cd into the backups directory first):
   ```sh
   age -d -i ~/.config/age/keys.txt vaultwarden-YYYY-MM-DD.tar.gz.age > vaultwarden.tar.gz
   ```

4. Extract the archive:
   ```sh
   tar -xzf vaultwarden-YYYY-MM-DD.tar.gz -C /home/hughboi/data/vaultwarden
   ```

5. Promote the hot backup as the canonical database. The archive contains both `db.sqlite3` (live at backup time, may have been mid-write) and `db-backup.sqlite3` (clean consistent snapshot). Always use the hot backup:
   ```sh
   mv /home/hughboi/data/vaultwarden/data/db-backup.sqlite3 \
      /home/hughboi/data/vaultwarden/data/db.sqlite3
   ```

6. Fix permissions:
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
   > Restic ignores `lchown` errors on NFS mounts — as long as the output says `Summary: Restored 1 files`, it worked.

3. Run an integrity check:
   ```sh
   sqlite3 /mnt/truenas/restic/tmp-for-restore/mnt/volumes/data/vaultwarden/data/db.sqlite3 \
     "PRAGMA integrity_check;"
   ```
   > If the output is anything other than `ok`, stop. Delete the temp file and repeat from step 2 with an older snapshot.

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

- A SQLite `VACUUM` is run once a year for database health maintenance, orchestrated via Ansible and Semaphore.
- SQLite is best as a host file on the system for easy backups, but databases like Postgres are better off as a docker volume. Better performance and you backup with pgdump anyways