# File Browser

**URL:** https://file.hughboi.cc
**Docs:** https://filebrowser.org/

Web-based file manager. Exposes the TrueNAS NFS mount (`/mnt/truenas`) as `/data` inside the container so I can browse, download, upload, and manage files from a browser.

## Stack

Single container. Runs as `1000:1000` (hughboi).

## Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `/mnt/truenas` | `/data` | TrueNAS NFS mount — root of the file tree |
| `/home/hughboi/data/filebrowser/db` | `/config` | SQLite database (users, settings) |

## First Run

1. Navigate to https://file.hughboi.cc
2. Default credentials on first boot: `admin` / `admin` — change immediately
3. Set the branding, sort order, and default directory under **Settings**

## Subpath / Base URL

The container is configured with `FB_BASEURL=/filebrowser`. If routing changes, update this env var to match.

## Upgrade Notes

- The SQLite database (`/config`) holds all user accounts, permissions, and settings. Back it up before upgrading.
- After upgrading the image, verify the admin login still works before assuming the upgrade is clean.

## Troubleshooting

**Files are read-only or permission errors on upload:**
- The TrueNAS NFS share must allow writes from UID 1000. On TrueNAS, under the NFS share, check that the dataset permissions allow write for the `hughboi` user.
- Confirm the container is running as `1000:1000`: `docker inspect filebrowser | grep -A2 User`

**Database locked error in logs:**
- Usually means two processes are writing to the SQLite DB simultaneously. Only ever run one replica of this container.
