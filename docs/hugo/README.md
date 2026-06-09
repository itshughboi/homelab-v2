# Homelab Docs — Hugo Site

Static documentation site built with [Hugo](https://gohugo.io) and the [Hugo Book](https://github.com/alex-shpak/hugo-book) theme.

> [!IMPORTANT]
> `content/` is **100% generated** from the docs source in `../` by [`sync.sh`](sync.sh). Never
> edit `content/` by hand — it gets wiped on every sync. Edit the markdown in `docs/<area>/`,
> then run `./sync.sh`.

---

## Syncing from `docs/`

```sh
cd docs/hugo
./sync.sh        # wipe + regenerate content/ from ../<area>/*.md
hugo build       # or ./setup.sh to preview live
```

What `sync.sh` does:
1. Wipes `content/` and mirrors every `docs/<area>/**.md` (plus `extras/`, `future/`,
   `QUICKSTART.md`, `Dependency-Map.md`) into it with **slugified** paths — lowercase,
   hyphenated, so `MAC Reservations.md` → `mac-reservations/`.
2. Renames each `index.md` / `README.md` → `_index.md` (Hugo section pages).
3. Injects front matter (`title` from the first `# H1`, `weight` from the area number).

Relative `.md` links in the source — including `../` up-references and `README.md`/`index.md`
→ section — are resolved at render time by
[`layouts/_default/_markup/render-link.html`](layouts/_default/_markup/render-link.html). A
`hugo build` that leaves a relative `.md` href unresolved almost always means a **broken link
in the source** — fix it in `docs/`. Wire `./sync.sh && hugo build` into CI to auto-publish.

---

## Prerequisites

```sh
brew install hugo go
```

Verify:
```sh
hugo version   # needs 0.112.0 or later (extended)
go version     # needs 1.21 or later
```

---

## Run Locally

```sh
cd docs/hugo
./setup.sh
```

Open `http://localhost:1313` in your browser. The page reloads automatically whenever you save a file — no manual refresh needed.

`setup.sh` does three things:
1. Checks that `hugo` and `go` are installed
2. Runs `hugo mod tidy` to fetch the Book theme (first run only — cached after that)
3. Starts the dev server with live reload

To stop: `Ctrl+C`

---

## Hugo Concepts

### How Content Becomes Pages

Hugo turns every `.md` file in `content/` into a web page. The URL mirrors the file path:

| File | URL |
| --- | --- |
| `content/_index.md` | `/` (home page) |
| `content/master-guide.md` | `/master-guide/` |
| `content/2-prep/_index.md` | `/2-prep/` (section page) |
| `content/2-prep/netboot.md` | `/2-prep/netboot/` |

### _index.md vs index.md

This trips people up. In Hugo, filenames matter:

| File | What it is |
| --- | --- |
| `_index.md` | **Section page** — the landing page for a folder. Shows in the sidebar as the parent item that collapses/expands. |
| `index.md` | **Leaf page** — treated as a standalone page, not a section. Won't appear as a collapsible parent in the sidebar. |

Every folder that should be a collapsible sidebar section needs `_index.md`, not `index.md`.

### Front Matter

Every Hugo page starts with a front matter block between `---` delimiters. This is how Hugo knows the page title, where to place it in the sidebar, and any special rendering options.

```yaml
---
title: "Page Title"           # what appears in the sidebar and browser tab
weight: 10                    # sidebar sort order — lower numbers appear first
bookCollapseSection: true     # makes this section collapsible in the sidebar
---
```

Weights control sort order within a section. The convention used here:

| Section | Weight |
| --- | --- |
| Master Guide | 5 |
| 1. Prep | 10 |
| 2. Networking | 20 |
| 3. Provisioning | 30 |
| ... | ... |

Sub-pages within a section use weights 10, 20, 30 to control their order within that section.

---

## Adding Content

### Add a New Page to an Existing Section

Create a `.md` file in the relevant section folder with front matter at the top:

```sh
# Example: add a new page to 8-k3s/
cat > content/8-k3s/helm-charts.md << 'EOF'
---
title: "Helm Charts"
weight: 20
---

# Helm Charts

Content here...
EOF
```

The page appears in the sidebar under "8. k3s" automatically.

### Add a New Section

Create a new folder with an `_index.md` inside it:

```sh
mkdir content/10-security
cat > content/10-security/_index.md << 'EOF'
---
title: "10. Security"
weight: 100
bookCollapseSection: true
---

# Security

Content here...
EOF
```

### Callouts (Note, Warning, Danger)

Hugo Book renders GitHub-style callouts as colored boxes. Use the same syntax as the source markdown:

```markdown
> [!NOTE]
> Informational note — blue.

> [!TIP]
> Helpful tip — green.

> [!IMPORTANT]
> Important info — purple.

> [!WARNING]
> Warning — yellow.

> [!CAUTION]
> Danger/caution — red.
```

> Requires `[markup.goldmark.renderer] unsafe = true` in `hugo.toml` — already set.

### Code Blocks

Fenced code blocks with language tags get syntax highlighting automatically:

````markdown
```sh
kubectl get nodes
```

```yaml
apiVersion: v1
kind: Pod
```

```hcl
resource "proxmox_vm_qemu" "athena" {}
```
````

Supported languages: `sh`, `bash`, `yaml`, `toml`, `hcl`, `python`, `go`, and [many more](https://gohugo.io/content-management/syntax-highlighting/#list-of-chroma-highlighting-languages).

---

## Site Configuration

`hugo.toml` controls the whole site. Key settings:

```toml
title = "hughboi homelab"        # browser tab + header
theme = "hugo-book"

[params]
  BookTheme = "auto"             # "auto" | "light" | "dark"
  BookToC = true                 # per-page table of contents (right side)
  BookSearch = true              # full-text search bar
  BookCollapseSection = true     # sidebar sections start collapsed
  BookRepo = "https://..."       # "Edit this page" link target
```

To disable the table of contents on a specific page, add to that page's front matter:
```yaml
bookToc: false
```

To hide a page from the sidebar entirely:
```yaml
bookHidden: true
```

---

## Build for Production

To generate a static site (HTML/CSS/JS) ready to deploy:

```sh
cd docs/hugo
hugo build
```

Output goes to `public/`. That folder contains the complete site — copy it anywhere (web server, S3, Cloudflare Pages, GitHub Pages, Gitea Pages).

### Deploy to Gitea Pages

```sh
hugo build
# Copy public/ to your Gitea Pages branch
# Or configure CI to run hugo build and publish automatically
```

### Deploy to Cloudflare Pages

Connect the repo in the Cloudflare Pages dashboard:
- Build command: `hugo`
- Build output directory: `public`
- Root directory: `docs/hugo`

Cloudflare rebuilds automatically on every push to `main`.

---

## File Structure

```
docs/hugo/
├── README.md              ← you are here
├── hugo.toml              ← site config (title, theme, params)
├── go.mod                 ← Go module — pins the hugo-book theme version
├── setup.sh               ← one-command local dev server
├── sync.sh                ← regenerates content/ from ../<area>/  (run this after editing docs)
├── layouts/_default/_markup/
│   └── render-link.html   ← resolves relative .md links → Hugo pages
├── static/                ← static assets
└── content/               ← GENERATED by sync.sh — do not edit by hand
    ├── _index.md          ← home (generated)
    ├── 1-networking/ … 8-gitops/   ← one section per docs area, mirroring docs/ structure
    ├── extras/  future/
    ├── quickstart/  dependency-map/
```

`content/` mirrors the `docs/` tree exactly (slugified, with `index.md`/`README.md` → `_index.md`).
To change a page, edit its source under `docs/<area>/` and re-run `./sync.sh`.

---

## Troubleshooting

**`hugo mod tidy` fails with module errors**

```sh
# Clear the module cache and retry
hugo mod clean
hugo mod tidy
```

**Theme not found after pulling the repo on a new machine**

```sh
./setup.sh   # runs hugo mod tidy which re-fetches the theme
```

**Port 1313 already in use**

```sh
hugo server --port 1314
```

**Callouts not rendering as colored boxes (showing as plain blockquotes)**

Ensure `hugo.toml` has:
```toml
[markup.goldmark.renderer]
  unsafe = true
```

**Page shows in the site but not in the sidebar**

Check that the file is named `_index.md` (not `index.md`) if it should be a section, and that `weight` is set in the front matter.

**Content looks different from the source markdown files**

`content/` is generated. If you edited a source file under `docs/<area>/` and the site still
shows the old version, you haven't re-synced — run `./sync.sh`, then rebuild.
