# image-audit

Audits Docker containers on dock-prod for images tagged `:latest`, untagged images, or images that haven't been updated in a long time.

## What it does

Inspects all running containers and reports any that are running on `:latest` (instead of a pinned version tag) or on very old image layers. Read-only — makes no changes.

## Run

```sh
cd ansible/playbooks/docker/image-audit
ansible-playbook -i inventory.yaml main.yaml
```

## Why

Pinned tags are the standard — `:latest` is unpredictable when you pull updates. This catches containers started manually outside of a compose file, or compose files where the tag slipped back to `:latest`.

## Schedule

Run monthly. Renovate handles automated tag-bump PRs; this catches anything Renovate misses or that was started outside of Git.

## Target

`docker_hosts` → `10.10.10.10` (dock-prod)
