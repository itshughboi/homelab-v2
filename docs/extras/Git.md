> [!NOTE] **Reference / extras** — git tips (sparse-checkout, etc.); **not** part of the rebuild sequence ([BUILD.md](../BUILD.md)).

### Two remotes exist — Gitea is canonical, GitHub is a one-way mirror

```sh
git remote -v
# origin  https://gitea.hughboi.cc/hughboi/homelab.git   (canonical — push here)
# github  https://github.com/itshughboi/homelab-v2.git   (mirror — do not push here manually)
```

The GitHub remote is a mirror **of** Gitea, not the other way around. A manual `git push
github main` doesn't break anything by itself (any host that clones from Gitea won't see it),
but it does mean GitHub can briefly show a commit Gitea doesn't have yet — confusing if you're
troubleshooting from a machine that clones from GitHub instead. If you push to the wrong remote
by accident, just push the same commit to `origin` too; there's no real conflict as long as
both remotes end up pointing at the same history.

**Always target `origin` explicitly if there's any ambiguity:** `git push origin main`.

### Exclude .env from being included
```
echo ".env" >> .gitignore
```

### Cloning specific folders/files using sparse checkout

> [!NOTE] What this achieves
> Essentially it allows me to git clone a singular repository, but only include specified folders/files so I'm not pulling down everything that I might not need

1. Clone repo without checkout (creates folder and .git only). 
```
git clone --no-checkout git@gitea.hughboi.cc:hughboi/Homelab.git code
cd code
```

> [!INFO] 'code at end of command above'
>  creates a directory named code in current directory

2. Initialize sparse checkout
```
git sparse-checkout init --cone
```
3. Set the files/folders I want
```
git sparse-checkout set docker-compose ansible .gitea/workflows dotfiles kubernetes
```
4. Checkout the branch (main/master)
```
git checkout main
```
