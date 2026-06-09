#!/usr/bin/env bash
# Regenerate hugo/content/ from the docs/ source tree.
#
# This replaces the old "hand-copy" workflow (which drifted constantly). The docs/ files are the
# single source of truth; this mirrors them into Hugo with slugified paths + injected front
# matter. Relative .md links are resolved at render time by layouts/_default/_markup/render-link.html.
#
# Run: docs/hugo/sync.sh   (then `./setup.sh` or `hugo build`)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"          # docs/hugo
SRC=".."                                      # docs/
DEST="content"

# lowercase, collapse non-alphanumerics to single hyphens, trim hyphens
slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'; }

# title = first markdown H1 (minus "# "), else humanized filename
title_of() {
  local f="$1" t
  t=$(grep -m1 -E '^# ' "$f" 2>/dev/null | sed -E 's/^# +//; s/"/\\"/g' || true)
  [ -n "$t" ] && { printf '%s' "$t"; return; }
  printf '%s' "$(basename "$f" .md)"
}

# full wipe — content/ is 100% generated from docs/ (no hand-maintained pages, no drift)
rm -rf "$DEST"
mkdir -p "$DEST"

# home / landing page
cat > "$DEST/_index.md" <<'EOF'
---
title: "hughboi homelab"
type: docs
---

# Homelab Documentation

Auto-generated from `docs/` by `sync.sh` — edit the source under `docs/`, never `content/`.
Pick a section from the sidebar: networking, proxmox, athena, storage, security, docker, k3s, gitops.
EOF

# sources to mirror: the 8 numbered areas + extras + future + every top-level .md
mapfile -t FILES < <(
  cd "$SRC"
  find 1-networking 2-proxmox 3-athena 4-storage 5-security 6-docker 7-k3s 8-gitops extras future \
       -type f -name '*.md' 2>/dev/null
  ls *.md 2>/dev/null          # BUILD.md, QUICKSTART.md, Dependency-Map.md, Backup-Recovery.md, …
)

for rel in "${FILES[@]}"; do
  src="$SRC/$rel"
  # slugify each path segment; index.md / README.md -> _index.md
  dir=$(dirname "$rel"); base=$(basename "$rel")
  outdir="$DEST"
  if [ "$dir" != "." ]; then
    IFS='/' read -ra segs <<< "$dir"
    for s in "${segs[@]}"; do outdir="$outdir/$(slug "$s")"; done
  fi
  if [ "$base" = "index.md" ] || [ "$base" = "README.md" ]; then
    outfile="$outdir/_index.md"
  else
    outfile="$outdir/$(slug "${base%.md}").md"
  fi
  mkdir -p "$outdir"

  # weight: top-level numbered sections sort by their number; pages default
  weight=""
  top="${rel%%/*}"
  if [[ "$base" == "index.md" || "$base" == "README.md" ]] && [[ "$top" =~ ^([0-9]+)- ]]; then
    weight="${BASH_REMATCH[1]}0"
  fi

  {
    printf -- '---\n'
    printf 'title: "%s"\n' "$(title_of "$src")"
    [ -n "$weight" ] && printf 'weight: %s\n' "$weight"
    printf -- '---\n\n'
    cat "$src"
  } > "$outfile"
done

echo "Synced ${#FILES[@]} files from docs/ → $DEST/"
