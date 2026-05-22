# image-update

Pulls the latest image layers for all pinned-tag Docker Compose services on dock-prod and recreates containers where the image changed.

## What it does

Finds all compose projects under `/home/hughboi/code`, runs `docker compose pull` on each, then `docker compose up -d` to recreate only containers where the image digest changed. Does **not** change tags — only pulls new layers for already-pinned versions.

## Run

```sh
cd ansible/playbooks/docker/image-update
ansible-playbook -i inventory.yaml main.yaml
```

## Notes

- Use this for patch releases within a pinned tag (e.g., `grafana:10.x.x` → latest `10.x.x` build)
- To change a tag (major/minor bumps), update the compose file first via a Renovate PR, then run this
- Projects can be skipped by adding them to `skip_projects` in the vars
- Sends ntfy notification on completion with a summary of what changed

## Schedule

Run weekly as a Semaphore job for routine patch updates.

## Target

`docker_hosts` → `10.10.10.10` (dock-prod)
