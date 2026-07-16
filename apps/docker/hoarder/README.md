# Hoarder

**URL:** https://hoarder.hughboi.cc
**Docs:** https://docs.hoarder.app/

AI-powered bookmarking app. Save links, it screenshots the page, archives the content, extracts text, and uses an LLM to auto-tag and summarize. Search across everything later.

## Stack

Three containers:

| Container | Image | Role |
|---|---|---|
| `hoarder` | `ghcr.io/hoarder-app/hoarder` | Main app + API |
| `hoarder-chrome` | `gcr.io/zenika-hub/alpine-chrome` | Headless Chrome — screenshots and page archiving |
| `hoarder-search` | `getmeili/meilisearch` | Full-text search index |

Chrome needs internet access to browse and archive URLs. The `hoarder` network is therefore not `internal`.

## Volumes

| Mount | Purpose |
|---|---|
| `data` (named volume) | All bookmark data, screenshots, archived content |
| `meilisearch` (named volume) | Search index |

> [!WARNING]
> These are **anonymous** named volumes (`volumes: data: / meilisearch:` with no explicit
> `name:` in `compose.yaml`) — Docker Compose auto-prefixes them with the **compose project
> name**, which defaults to the basename of the directory you run `docker compose`/`sops-deploy`
> from. As long as that's `apps/docker/hoarder/` (project name `hoarder`), the real volumes are
> `hoarder_data`/`hoarder_meilisearch` and everything lines up. But if this ever gets deployed
> from a differently-named directory, or the Ansible `docker_compose_v2` module ever sets an
> explicit different `project_name`, Compose will silently create **brand-new empty volumes**
> instead of attaching to your real bookmark data — no error, no warning. Before any deploy from
> a new/different path, verify first: `docker compose config | tail -5` should show
> `hoarder_data`/`hoarder_meilisearch`. See
> [docs/Backup-Recovery.md](../../../docs/Backup-Recovery.md#ad-hoc-back-up-a-docker-named-volume-before-a-risky-change)
> for the full check + backup pattern used when this was originally migrated.

**Status:** migrated to SOPS and deployed via `sops-deploy`/Semaphore — confirmed healthy and
confirmed attached to the pre-existing `hoarder_data`/`hoarder_meilisearch` volumes (verified
`docker compose config | tail -5` showed the right names *before* cutover, and `docker volume ls`
showed the same two volumes, unchanged, after). No manual SSH needed for the deploy itself.

## Environment Variables (`.env`)

| Variable | Purpose |
|---|---|
| `NEXTAUTH_SECRET` | Random secret for session signing — generate with `openssl rand -base64 32` |
| `NEXTAUTH_URL` | Must match the public URL: `https://hoarder.hughboi.cc` |
| `MEILI_MASTER_KEY` | Meilisearch master key — generate with `openssl rand -base64 32` |
| `OPENAI_API_KEY` | Optional — enables AI tagging and summarization |
| `OPENAI_BASE_URL` | Override to point at a local Ollama or other OpenAI-compatible endpoint |

## First Run

1. Create `.env` from `.env.example` and fill in `NEXTAUTH_SECRET`, `NEXTAUTH_URL`, `MEILI_MASTER_KEY`
2. Optionally add `OPENAI_API_KEY` for AI features
3. `docker compose up -d`
4. Navigate to https://hoarder.hughboi.cc and create your account

## Using a Local LLM (Ollama)

Instead of OpenAI, point Hoarder at a local Ollama instance:
```
OPENAI_BASE_URL=http://10.10.10.10:11434/v1
OPENAI_API_KEY=ollama
```
Set `INFERENCE_TEXT_MODEL` and `INFERENCE_IMAGE_MODEL` to the Ollama model names you have pulled.

## Upgrade Notes

- Both `data` and `meilisearch` named volumes persist across upgrades.
- Meilisearch occasionally requires a full re-index after major version bumps — Hoarder handles this automatically on startup, but it may take a few minutes.
- Keep `hoarder` and `hoarder-search` version pins in sync (check the Hoarder release notes for the required Meilisearch version).

## Troubleshooting

**Screenshots not generating:**
- Check Chrome container logs: `docker logs hoarder-chrome`
- Chrome listens on port 9222. Verify the main app can reach it: `docker exec hoarder wget -qO- http://chrome:9222/json/version`

**Search not returning results:**
- Meilisearch may need to re-index. Check `docker logs hoarder-search`
- Trigger a manual re-index from Hoarder admin settings if available

**AI tags not appearing:**
- Confirm `OPENAI_API_KEY` is set and valid
- Check logs for rate limit or auth errors from the AI provider

**Forgot which account/email you registered with:**
- Hoarder stores users in its own internal SQLite DB (`db.db` inside the `data` volume) — no
  separate user-management UI or CLI command ships with the image. Copy the DB out (never query
  the live file directly) and inspect it read-only:
  ```sh
  docker cp hoarder:/data/db.db /tmp/hoarder-db-readonly.db
  sqlite3 /tmp/hoarder-db-readonly.db "SELECT id, email, name FROM user;"
  rm /tmp/hoarder-db-readonly.db   # don't leave a copy of the user table lying around
  ```
  If `sqlite3` isn't installed on the host, `sudo apt install sqlite3` (Ubuntu) first. This same
  copy-out-then-query pattern works for any SQLite-backed container, not just this one.
