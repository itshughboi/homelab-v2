# docs — self-hosted Hugo site

The internal equivalent of GitHub Pages: serves the Hugo docs at `https://docs.hughboi.cc`
behind Traefik. **Scaffold — not yet deployed.** Intended for when the repo moves to Gitea.

| | |
|---|---|
| **Source of truth** | `docs/` (built by `docs/hugo/sync.sh` + Hugo) |
| **Image** | locally built (multi-stage `Dockerfile` → nginx); not pulled |
| **Domain** | `docs.hughboi.cc` (internal — front with Authentik forward-auth if you want it gated) |
| **Deploy** | `.gitea/workflows/docs-deploy.yaml` on push to `main` |

## Deploy paths
- **GitHub (now):** [`.github/workflows/docs-pages.yaml`](../../../.github/workflows/docs-pages.yaml) → GitHub Pages at `https://itshughboi.github.io/homelab-v2/`.
- **Gitea (this):** [`.gitea/workflows/docs-deploy.yaml`](../../../.gitea/workflows/docs-deploy.yaml) → builds this image, redeploys the container. Immutable: each push rebuilds a fresh image.

Both coexist (GitHub ignores `.gitea/`, Gitea ignores `.github/`). When you fully cut over to
Gitea, this is the live one.

## Manual bring-up
```sh
docker compose -f apps/docker/docs/compose.yaml up -d --build
```
The build context is the **repo root** (the Hugo build needs `docs/` + `sync.sh` + `go.mod`).
`BOOK_REPO` is overridden to internal Gitea so the "Edit this page" links point there (the
`hugo.toml` default is the public GitHub repo, for the Pages site).

## To gate access (optional)
Add Authentik forward-auth to the secure router, e.g.:
```
traefik.http.routers.docs-secure.middlewares=authentik@docker
```
