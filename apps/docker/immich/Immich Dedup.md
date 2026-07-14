# Immich Duplicate Cleanup

## Overview

Immich's built-in duplicate review UI (`Utilities → Duplicate Review`) times out and fails to render at large library sizes (~35k+ duplicate groups). The Immich "Deduplicate All" button in the UI is also unreliable at scale.

This runbook covers:
1. The Traefik timeout fix required for long-running API calls
2. A Python script to bulk-delete duplicates using Immich's own detection

---

## Traefik Timeout Fix

The `/api/duplicates` endpoint takes several minutes to respond on large libraries. Without this fix, Traefik kills the connection with a 502 after ~30 seconds. This also affects large video uploads.

Add to `./data/traefik.yml` under the `https` entrypoint:

\```yaml
entryPoints:
  https:
    address: ":443"
    http:
      middlewares:
        - crowdsec-bouncer@file
    transport:
      respondingTimeouts:
        readTimeout: "0s"
        writeTimeout: "0s"
        idleTimeout: "0s"
\```

Then restart Traefik:

\```bash
docker compose up -d traefik
\```

---

## Duplicate Cleanup Script

**Location:** `docs/4-storage/immich_dedup.py`

Uses Immich's own duplicate detection (`GET /api/duplicates`). For each duplicate group, keeps the **largest file** (tiebreaker: oldest upload date) and deletes the rest.

### Prerequisites

- Python 3 (no external dependencies)
- An Immich API key: **User Settings → API Keys → New API Key**
- Immich reachable at its URL

### Usage

**Dry run (safe, no deletions):**
\```bash
python3 immich_dedup.py --url https://eros.hughboi.cc --key YOUR_API_KEY
\```

**Test on first 20 groups (sent to Trash, recoverable):**
\```bash
python3 immich_dedup.py --url https://eros.hughboi.cc --key YOUR_API_KEY --execute --limit 20
\```

**Full run (sent to Trash):**
\```bash
python3 immich_dedup.py --url https://eros.hughboi.cc --key YOUR_API_KEY --execute
\```

**Full run, permanent delete (skip Trash):**
\```bash
python3 immich_dedup.py --url https://eros.hughboi.cc --key YOUR_API_KEY --execute --force --yes
\```

### Flags

| Flag | Description |
|---|---|
| `--execute` | Actually delete (default is dry run) |
| `--force` | Permanent delete, bypasses Trash |
| `--limit N` | Only process first N duplicate groups |
| `--batch-size N` | Assets per delete request (default 100) |
| `--yes` | Skip confirmation prompt |
| `--timeout N` | Seconds to wait for duplicate fetch (default 900) |
| `--insecure` | Skip TLS verification (not needed with valid cert) |
| `--cafile PATH` | Path to custom CA bundle |
| `--log PATH` | Log file path (default: immich_dedup.log) |

### Behavior

- Default delete mode sends assets to **Immich Trash** (recoverable for ~30 days)
- Add `--force` to skip Trash and permanently delete
- Failed batches are retried individually so one bad ID doesn't abort the run
- Everything is logged to `immich_dedup.log`
- Assets with `null` EXIF data are treated as size 0 and will be the loser in any group

### Recommended Run Order

\```bash
# 1. Dry run — verify what it would do
python3 immich_dedup.py --url https://eros.hughboi.cc --key YOUR_KEY

# 2. Small live test — first 20 groups to Trash
python3 immich_dedup.py --url https://eros.hughboi.cc --key YOUR_KEY --execute --limit 20

# 3. Check Immich Trash looks right, then full run
python3 immich_dedup.py --url https://eros.hughboi.cc --key YOUR_KEY --execute

# 4. Once happy, empty Trash in Immich UI or re-run with --force
\```

### Notes

- The fetch step will look frozen for several minutes on large libraries — this is normal
- Monitor with `docker stats immich_server_eros` to confirm server activity during fetch
- After cleanup, run **Administration → Jobs → Duplicate Detection** again to verify clean
- Revoke the API key after use if it was generated specifically for this task