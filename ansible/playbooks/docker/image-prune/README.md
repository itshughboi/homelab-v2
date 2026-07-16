Reclaim disk space from unused Docker images — safely, without a time-based cutoff.

## Why not just `docker image prune -a --filter until=720h`

Docker doesn't track true "last used" timestamps for images, only creation time. A time-based
filter risks removing an image you deliberately pulled and plan to run again, just because it
happens to be N days old. This playbook uses a more conservative signal instead: has this image
**ever** backed a container, running or stopped? If yes, it's kept regardless of age.

## What it removes

1. **Dangling images** — no tag at all, can't be run by name, always safe to remove.
2. **Tagged images with zero containers ever created from them** — matched by image ID via
   `docker ps -a --filter ancestor=<id>`, not by string-comparing repo:tag names (which breaks
   silently if an image's been retagged or a container references it by digest).

Everything else — including stopped containers' images, and images you've pulled but not yet
run through a container that still exists (even stopped) — is left alone.

## Usage

```sh
ansible-playbook -i inventory.yaml main.yaml
```

**As a Semaphore Task Template:** run on a schedule (e.g. weekly) — no Survey Variables needed,
it targets all `docker_hosts`. Reports results via ntfy (`ntfy.hughboi.cc/homelab`) either way —
success shows counts removed + `docker system df` output, failure alerts urgently.

## Replaces

The old `ansible/playbooks/docker/prune-docker.yaml` (unscoped `hosts: all`, and — despite its
name — `images_filters: { dangling: false }` actually meant "don't filter to dangling-only,"
i.e. it pruned *every* unused image regardless of whether it had ever backed a container. Never
scheduled or referenced anywhere; removed in favor of this playbook.
