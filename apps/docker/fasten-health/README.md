# Fasten Health

**URL:** https://fastenhealth.hughboi.cc
**Docs:** https://docs.fastenhealth.com/

Self-hosted personal health records aggregator. Connects to healthcare providers (hospitals, labs, insurance) via FHIR/SMART-on-FHIR to pull medical records, test results, medications, and claims into one place.

## Stack

Single container. SQLite database stored in `/opt/fasten/db` (mounted from host). Config at `/opt/fasten/config/config.yaml` (`:ro`, mounted from this repo checkout).

## Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `/home/hughboi/data/fastenhealth/db` | `/opt/fasten/db` | SQLite database — all health records |
| `/home/hughboi/data/fastenhealth/cache` | `/opt/fasten/cache` | Provider metadata cache |
| `/home/hughboi/data/fastenhealth/certs` | `/opt/fasten/certs/shared` | Shared TLS certs (unused unless `web.https` is enabled) |
| `./config.yaml` (this repo checkout) | `/opt/fasten/config/config.yaml:ro` | Server config — database, JWT signing key |

## Secrets (SOPS)

Two separate secret files, both SOPS-encrypted:

- `.env` (`.env.sops`) — `FASTEN_ENCRYPTION_KEY`, used by the app for at-rest encryption of certain fields
- `config.yaml` (`config.yaml.sops`, config-as-secret pattern like mailrise) — contains the real `jwt.issuer.key` used to sign session tokens. Tracked placeholder is `config.yaml.example`.

**Database encryption is intentionally disabled** (`database.encryption.enabled: false` in `config.yaml`) — this matches what's actually running in production; it was not silently left off, it's a deliberate choice made when this was migrated to SOPS in 2026-07. Revisit only as its own deliberate decision, since enabling it after the fact on an existing unencrypted SQLite DB is not just a config flip.

## First Run

1. `git pull`, then decrypt secrets: `./scripts/sops-run.sh fasten-health config` to verify
2. `docker compose up -d`
3. Navigate to https://fastenhealth.hughboi.cc
4. Create your account
5. Connect health providers: **Sources → Add Source** → search for your provider

## Connecting Providers

Fasten supports hundreds of US healthcare providers via FHIR. The connection process:
1. Select your provider from the list
2. You'll be redirected to the provider's patient portal to authenticate
3. Authorize Fasten to read your records
4. Records sync automatically

## Upgrade Notes

- The SQLite database in `/home/hughboi/data/fastenhealth/db` holds all health records. Back it up before upgrading.
- Image is pinned to `main-v1.1.3` — the bare `v1.1.3` tag does not exist on `ghcr.io/fastenhealth/fasten-onprem`; only `main-v1.1.3`/`sandbox-v1.1.3` style tags are published for this version. Confirm a new tag actually exists before bumping (`curl` the registry's tag list) rather than assuming semver-only tags will resolve.
- Check the [Fasten Health releases](https://github.com/fastenhealth/fasten-onprem/releases) for migration notes.
