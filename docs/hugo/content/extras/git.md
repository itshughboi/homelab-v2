---
title: "Git"
---

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
