# postgres-maintenance

Runs `VACUUM ANALYZE` on every database in every running PostgreSQL container on dock-prod and reports table bloat.

## What it does

Finds all containers using a Postgres image, connects to each, and runs `VACUUM ANALYZE` on all user databases. Also reports database sizes and flags tables with high dead tuple ratios. Does not stop containers — VACUUM does not lock tables.

## Run

```sh
cd ansible/playbooks/docker/postgres-maintenance
ansible-playbook -i inventory.yaml main.yaml
```

## Affected services

n8n, Gitea, Paperless-ngx, Immich, Home Assistant, Mealie — anything backed by a Postgres container on dock-prod.

## Schedule

Monthly in Semaphore. Without periodic vacuuming, dead tuple accumulation causes noticeable query slowdowns over months.

## Target

`docker_hosts` → `10.10.10.10` (dock-prod)
