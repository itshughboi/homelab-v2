# NFS Client Mounts (dock-prod → TrueNAS)

Canonical reference for how **dock-prod** (`10.10.10.10`) mounts the TrueNAS shares
(`10.10.10.5`, pool "The Archive"). All app bind-mounts that point at `/mnt/truenas/*`
depend on these being mounted with the **right options** — get the options wrong and an
app can silently read/write an empty *local* directory instead of the share.

## The rule: never use bare `defaults`

Every NFS line in `/etc/fstab` **must** carry `_netdev,nofail,hard` (in addition to
`defaults`). Bare `defaults` caused the 2026-07-17 restic data-loss incident
([#44](https://gitea.hughboi.cc/hughboi/homelab/issues/44)): on a boot race (mount tried
before the network was up) or a transient NFS drop, the share stayed unmounted, so
`/mnt/truenas/restic` was just an empty directory on dock-prod's root disk — restic
backed up into it and, on redeploy, re-initialized a fresh repo over the empty path,
destroying the history. Nothing was ever deleted on TrueNAS.

| Option | Why |
| --- | --- |
| `_netdev` | Treat as a network device: wait for the network before mounting at boot, and unmount before the network goes down. Prevents the boot-race empty-dir trap. |
| `nofail` | Don't block/abort boot if TrueNAS is unreachable. The mount comes up later (with `_netdev`) instead of dropping you to an emergency shell. |
| `hard` | On an NFS timeout, **block and retry** rather than return an I/O error. `soft` can return errors mid-write → silent corruption/partial data. Always prefer `hard` for data mounts. |
| `bg` | (eros only) Retry the mount in the background if the first attempt fails, so boot isn't held up. |
| `vers=3` | (jellyfin, romm) Pin NFSv3 where the client/app needs it. Keep it — just append the safety flags. |

> `nofail` is a boot-time flag and does **not** appear in the runtime `mount` output —
> that's expected. Verify it by reading `/etc/fstab`, not `mount`.

## Current fstab (dock-prod `/etc/fstab`)

```
10.10.10.5:/mnt/The\040Archive/Liyah                              /mnt/truenas/liyah      nfs defaults,_netdev,nofail,hard 0 0
10.10.10.5:/mnt/The\040Archive/Restic                             /mnt/truenas/restic     nfs defaults,_netdev,nofail,hard 0 0
10.10.10.5:/mnt/The\040Archive/Epoch-1/Legacy/Documents/Financial /mnt/truenas/paperless nfs defaults,_netdev,nofail,hard 0 0
10.10.10.5:/mnt/The\040Archive/Epoch-2/Pictures                   /mnt/truenas/immich     nfs defaults,_netdev,nofail,hard 0 0
10.10.10.5:/mnt/The\040Archive/Epoch-1/Legacy/Pictures            /mnt/truenas/immich2    nfs defaults,_netdev,nofail,hard 0 0
10.10.10.5:/mnt/The\040Archive/Jellyfin                           /mnt/truenas/jellyfin   nfs defaults,vers=3,_netdev,nofail,hard 0 0
10.10.10.5:/mnt/The\040Archive/Music                              /mnt/truenas/music      nfs defaults,_netdev,nofail,hard 0 0
10.10.10.5:/mnt/The\040Archive/YT-Audios                          /mnt/truenas/yt-audios  nfs defaults,_netdev,nofail,hard 0 0
10.10.10.5:/mnt/The\040Archive/Eros                               /mnt/truenas/eros       nfs defaults,bg,_netdev,nofail,hard 0 0
10.10.10.5:/mnt/The\040Archive/Gaming/Romm                        /mnt/truenas/romm       nfs defaults,_netdev,nofail,hard 0 0
```

(Spaces in the TrueNAS dataset path are escaped as `\040` in fstab.)

## Adding a new mount

```sh
sudo mkdir -p /mnt/truenas/<name>
# append to /etc/fstab (mind the \040 for the space in "The Archive"):
echo '10.10.10.5:/mnt/The\040Archive/<Dataset> /mnt/truenas/<name> nfs defaults,_netdev,nofail,hard 0 0' | sudo tee -a /etc/fstab
sudo mount /mnt/truenas/<name>
```

Changing `soft`→`hard` (or otherwise changing conflicting options) needs a full cycle,
not a remount: `sudo umount /mnt/truenas/<name> && sudo mount /mnt/truenas/<name>`.

## Verifying / catching regressions

```sh
# Is every NFS share actually mounted (not an empty local dir)?  ext2/3 fstype = NOT mounted.
for p in /mnt/truenas/*; do printf '%-28s %s\n' "$p" "$(mountpoint -q "$p" && stat -f -c %T "$p" || echo NOT-MOUNTED)"; done
```

The `nfs-health` Ansible playbook (`ansible/playbooks/ubuntu/nfs-health/`) checks that
each fstab NFS entry is mounted + writable and re-mounts stale ones, alerting to ntfy
`homelab` on failure. It verifies *mounted*, not *options* — this doc is the source of
truth for the options.

## Known issue: `paperless` export access-denied

As of 2026-08-12, `/mnt/truenas/paperless`
(`10.10.10.5:/mnt/The Archive/Epoch-1/Legacy/Documents/Financial`) fails to mount with
`access denied by server` — dock-prod is not permitted by that dataset's NFS export, so
paperless has been running off a **local** directory at the mountpoint, not the share.
The fstab options are correct; the fix is on the **TrueNAS side** (add dock-prod
`10.10.10.10` to the Financial dataset's NFS share allow-list, or correct the export
path), then `sudo mount /mnt/truenas/paperless` and confirm `fstype=nfs`.
