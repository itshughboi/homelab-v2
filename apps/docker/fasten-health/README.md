Not fully setup. Production has an encrypted database, so figure out how to do that before this is officially done. The config.yaml is new to me. I hadn't been running it the whole time but I should so that database can be encrypted. Current implementation doesn't even use the config.yaml file, but to fully setup in production, I should be using that <br>

```sh
database:
  encryption:
    enabled: false
  #    key: ''
```

<br>
^^ this will need to be changed to <br>

```sh
enabled: true
```

---

# Fasten Health

**URL:** https://fastenhealth.hughboi.cc
**Docs:** https://docs.fastenhealth.com/

Self-hosted personal health records aggregator. Connects to healthcare providers (hospitals, labs, insurance) via FHIR/SMART-on-FHIR to pull medical records, test results, medications, and claims into one place.

## Stack

Single container. SQLite database stored in `/opt/fasten/db` (mounted from host). Config at `/opt/fasten/config/config.yaml` (`:ro`).

## Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `/home/hughboi/data/fasten-health/db` | `/opt/fasten/db` | SQLite database — all health records |
| `/home/hughboi/fastenhealth/config.yaml` | `/opt/fasten/config/config.yaml:ro` | Server config (encryption key, settings) |
| `cache` (named volume) | `/opt/fasten/cache` | Provider metadata cache |

## Config File

The config.yaml controls database encryption and other server settings. Must be set up before first run if using encryption:

```yaml
database:
  encryption:
    enabled: true
    key: 'YOUR_ENCRYPTION_KEY_HERE'
```

Generate a key: `openssl rand -hex 32`

**Once the database is created with encryption enabled, the key cannot be changed without losing access to all records.**

## First Run

1. Create the config.yaml at `/home/hughboi/fastenhealth/config.yaml` with encryption enabled
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

- The SQLite database in `/home/hughboi/data/fasten-health/db` holds all health records. Back it up before upgrading.
- If encryption is enabled, the encryption key must be present in config.yaml for the app to start.
- Check the [Fasten Health releases](https://github.com/fastenhealth/fasten-onprem/releases) for migration notes.
