# Mealie

**URL:** https://mealie.hughboi.cc
**Docs:** https://docs.mealie.io/

Self-hosted recipe manager and meal planner. Import recipes from URLs, organize them, plan meals for the week, and generate shopping lists.

## Stack

Single container. Uses an internal SQLite or Postgres database (configured via env). All app data is in the `data` named volume.

## Volumes

| Mount | Purpose |
|---|---|
| `data` (named volume) | All Mealie data — recipes, images, users, meal plans |

## Environment Variables (`.env`)

| Variable | Purpose |
|---|---|
| `ALLOW_SIGNUP` | `false` to disable open registration after initial setup |
| `DEFAULT_EMAIL` | Admin account email |
| `DEFAULT_PASSWORD` | Admin account password — change on first login |
| `BASE_URL` | Must match the public URL: `https://mealie.hughboi.cc` |
| `DB_ENGINE` | `sqlite` (default) or `postgres` for external DB |
| `POSTGRES_*` | Only needed if `DB_ENGINE=postgres` |

## First Run

1. Fill in `.env`
2. `docker compose up -d`
3. Navigate to https://mealie.hughboi.cc
4. Log in with the `DEFAULT_EMAIL` and `DEFAULT_PASSWORD` from `.env`
5. Change the admin password immediately under **Profile → Security**
6. Disable signups if this is a private instance: **Admin → Site Settings → Allow Registration = Off**

## Importing Recipes

- Paste a URL into the recipe importer — Mealie scrapes the page and extracts the recipe automatically
- Supports bulk import via OPML, Nextcloud Cookbook format, or direct JSON
- Mealie-native recipe format can be exported/imported for backups

## Upgrade Notes

- All data is in the `data` named volume. Back it up before upgrading:
```sh
docker run --rm -v mealie_data:/data -v $(pwd):/backup alpine \
  tar czf /backup/mealie-backup-$(date +%F).tar.gz -C / data
```
- Check the [Mealie changelog](https://github.com/mealie-recipes/mealie/releases) — there have been breaking migrations between major versions (particularly v0 → v1).

## Troubleshooting

**Recipe import fails on certain URLs:**
- Some sites block scrapers. Try the "Debug Scrape" option in the importer to see what Mealie is getting back.
- Manual entry is always available as a fallback.

**Data volume fills up:**
- Mealie stores full-resolution recipe images. If space is tight, look under **Admin → Maintenance → Clean Images** to remove orphaned images.
