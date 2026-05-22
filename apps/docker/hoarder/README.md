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
