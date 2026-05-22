# volume-backup

Backs up named Docker volumes to TrueNAS NFS as timestamped `.tar.gz` archives.

## What it does

Tars each named Docker volume into `/mnt/truenas/docker-volume-backups/`, keeps the last 7 backups per volume, and prunes older ones. Runs as a **hot backup** — containers are not stopped.

## Run

```sh
cd ansible/playbooks/docker/volume-backup
ansible-playbook -i inventory.yaml main.yaml
```

## Notes

- **Not for databases** — use the dedicated Vaultwarden and Postgres backup playbooks for any database volume. Those handle consistency properly. This is for stateless/config volumes (app data, configs, uploads).
- Volumes skipped by default: redis caches and Elasticsearch volumes (`romm_redis_data`, `archivist-redis`, `archivist-es`)
- Add any other volatile/unimportant volumes to `skip_volumes` in vars

## Schedule

Weekly in Semaphore.

## Target

`docker_hosts` → `10.10.10.10` (dock-prod)
