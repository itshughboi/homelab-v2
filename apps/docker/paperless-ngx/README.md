### Troubleshooting
###### Permission Denied
1. Create user on TrueNAS for paperless. Take note of UID & GID. 
2. Create the NFS share and set the **Mapall User** to be **hughboi** and save
3. Put UID & GID in .env of docker project
4. Stand up and should be good to do

---

# Paperless-ngx

**URL:** https://paperless.hughboi.cc
**Docs:** https://docs.paperless-ngx.com/

Document management system. Scan, OCR, tag, and search all paper documents. Replaces physical filing. Documents are imported from the TrueNAS consume directory, OCR'd by Tika, converted to searchable PDF by Gotenberg, and stored with full-text search.

## Stack

| Container | Role |
|---|---|
| `paperless-webserver` | Main app + web UI |
| `paperless-db` | PostgreSQL — document metadata and search index |
| `paperless-broker` | Redis — task queue for async processing |
| `paperless-gotenberg` | Chromium-based PDF converter (converts DOCX, HTML, etc. to PDF) |
| `paperless-tika` | Apache Tika — content extraction from Office docs |

## Network Layout

- `paperless` network: internal — all five containers communicate here
- `proxy` network: webserver joins this for Traefik

## Volumes

| Mount | Purpose |
|---|---|
| `data` (named volume) | Paperless app data — index, thumbnails, classification models |
| `media` (named volume) | Stored documents (the actual files after import) |
| `export` (named volume) | Document export target |
| `/mnt/truenas/paperless` | NFS consume directory — drop files here to auto-import |
| `pgdata` (named volume) | PostgreSQL data |
| `redisdata` (named volume) | Redis data |

## Import Flow

1. Drop files into the TrueNAS NFS share (`/mnt/truenas/paperless` on the host)
2. Paperless watches the consume directory and auto-imports
3. Tika extracts content from non-PDF formats
4. Gotenberg converts to searchable PDF if needed
5. OCR runs (Tesseract) and the document becomes searchable
6. Apply tags, correspondents, and document types either manually or via rules

## Key Environment Variables (`.env`)

| Variable | Purpose |
|---|---|
| `PAPERLESS_ADMIN_USER` | Admin account username |
| `PAPERLESS_ADMIN_PASSWORD` | Admin account password |
| `PAPERLESS_DBPASS` | Postgres password |
| `PAPERLESS_SECRET_KEY` | Django secret key — generate with `openssl rand -base64 32` |
| `PAPERLESS_OCR_LANGUAGES` | Languages to install for OCR (e.g. `eng deu`) |
| `PAPERLESS_TIME_ZONE` | `America/Denver` |

## First Run

1. Fill in `.env`
2. `docker compose up -d`
3. Navigate to https://paperless.hughboi.cc
4. Log in with `PAPERLESS_ADMIN_USER` and `PAPERLESS_ADMIN_PASSWORD`
5. Set up tags, document types, and correspondents under **Settings**
6. Configure auto-matching rules for automatic tagging

## Backup

```sh
# DB backup
docker exec paperless-db pg_dump -U paperless paperless > paperless-db-$(date +%F).sql

# Document backup (the actual files)
# The media named volume and /mnt/truenas/paperless are covered by Restic
```

## Upgrade Notes

- Paperless-ngx follows a fast release cycle. Check the [changelog](https://github.com/paperless-ngx/paperless-ngx/releases) for database migration notes before upgrading.
- The DB migration runs automatically on startup — back up `pgdata` before upgrading.
- Tika and Gotenberg versions should be updated in sync with the Paperless-ngx release notes (they specify compatible versions).

## Troubleshooting

**Documents stuck in consume directory, not importing:**
- Check `docker logs paperless-webserver` for consumer errors
- Verify the NFS consume path is mounted: `ls /mnt/truenas/paperless`
- File format may be unsupported — Paperless processes PDF, images, DOCX, TXT

**OCR producing garbled text:**
- The OCR language pack for the document's language may not be installed. Add the language code to `PAPERLESS_OCR_LANGUAGES` in `.env` and restart.

**Tika/Gotenberg not converting Office files:**
- Confirm both containers are running and healthy: `docker ps | grep paperless`
- Check that `PAPERLESS_TIKA_ENABLED=1` and the endpoint URLs are correct in compose
