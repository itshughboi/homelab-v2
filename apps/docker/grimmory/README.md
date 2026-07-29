# Grimmory

**URL:** https://grimmory.hughboi.cc
**Docs:** https://github.com/grimmory-tools/grimmory

Self-hosted digital library and ereader — EPUB/MOBI/AZW/PDF/CBZ/CBR/audiobook management with a
built-in browser reader, metadata enrichment, and OPDS/Kobo/KOReader sync. Community fork of
Booklore.

## Stack

Two containers: `grimmory` (app, port 6060 internally) and `grimmory-db` (MariaDB 11.4.8,
LinuxServer image). App waits on the DB's healthcheck before starting.

## Secrets

`DATABASE_PASSWORD`, `MYSQL_PASSWORD` (must match `DATABASE_PASSWORD` — same app user, read by
both containers), and `MYSQL_ROOT_PASSWORD`. See `.env.example`. Fill in `.env`, then:

```sh
./scripts/sops-migrate.sh grimmory
git add apps/docker/grimmory/.env.sops
git commit -m "chore(grimmory): encrypt secrets with sops"
```

## Deploy

```sh
cd apps/docker/grimmory
./scripts/sops-run.sh grimmory up -d
```

(or from repo root: `./scripts/sops-run.sh grimmory up -d`)

## Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `./data` | `/app/data` | Application data |
| `./books` | `/books` | Book library storage — point your imports/uploads here |
| `./bookdrop` | `/bookdrop` | Watched folder — drop files here for automatic import |
| `./config` | `/config` (grimmory-db) | MariaDB data directory |

## First Run

1. Navigate to https://grimmory.hughboi.cc and create the admin account
2. Drop EPUB/MOBI/PDF/CBZ/etc. files into `./bookdrop` for automatic import, or upload directly
   in the UI
3. Optional: wire up Pocket-ID OIDC (see other services' READMEs, e.g. `hoarder`, for the
   `OAUTH_*` var pattern) if you want SSO instead of local accounts — set `FORCE_DISABLE_OIDC=false`
   (already the default here) and add the OIDC env vars once configured

## Upgrade Notes

- Version is pinned via image tag (`v0.38.2`) — check [Grimmory releases](https://github.com/grimmory-tools/grimmory/releases)
  before bumping.
- `DATABASE_URL` uses the JDBC MariaDB driver — don't change the `jdbc:mariadb://` scheme.
