# Syncthing

**URL:** https://syncthing.hughboi.cc
**Docs:** https://docs.syncthing.net/

Continuous file synchronization. Syncs folders between devices (laptops, phones, servers) peer-to-peer without a cloud intermediary. Used for syncing documents, photos from phones, and config files across machines.

## Stack

Single container. Runs as `1000:1000`.

## Ports

| Port | Protocol | Purpose |
|---|---|---|
| `22000` | TCP | File transfer — **must be open to LAN** |
| `22000` | UDP | QUIC file transfer — **must be open to LAN** |
| `21027` | UDP | Local discovery broadcasts |
| `8384` | TCP | Web UI (via Traefik on `syncthing.hughboi.cc`) |

Ports 22000 (TCP+UDP) and 21027 (UDP) must be reachable from all devices that sync to this instance. If syncing from outside the LAN, these also need to be forwarded through the router or accessible via Tailscale.

## Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `/home/hughboi/data/syncthing/` | `/var/syncthing` | Syncthing config, database, and all synced folder data |

All synced folder data lives under `/home/hughboi/data/syncthing/` on the host by default. When adding a new sync folder, set its path to a subdirectory here (e.g. `/var/syncthing/docs`).

## First Run

1. `docker compose up -d`
2. Navigate to https://syncthing.hughboi.cc
3. Set the admin password immediately: **Actions → Settings → GUI → GUI Authentication Password**
4. Note the **Device ID** from **Actions → Show ID** — you'll need this to pair with other devices
5. On each device: install Syncthing, add this instance as a remote device using the Device ID
6. Share folders between devices as needed

## Adding a Device

1. On the device to add: open Syncthing UI, note its Device ID
2. On the server: go to **Add Remote Device**, paste the Device ID, give it a name
3. On the new device: accept the incoming device request from the server
4. Share a folder: on the server, click a folder → **Edit → Sharing → check the new device**
5. On the new device: accept the incoming folder share

## Pairing with Phone

- **Android:** [Syncthing-Fork](https://play.google.com/store/apps/details?id=com.github.catfriend1.syncthingandroid) (maintained fork)
- **iOS:** [Mobius Sync](https://apps.apple.com/app/mobius-sync/id1539203216) (paid, but good) or [Syncthing](https://apps.apple.com/app/syncthing/id1106547196)

## Upgrade Notes

- Config and synced data are all in `/home/hughboi/data/syncthing/`. Back this up before major upgrades.
- Syncthing is generally very stable across versions. Check the [release notes](https://github.com/syncthing/syncthing/releases) for protocol version changes before upgrading — a major protocol bump requires upgrading all connected devices around the same time.

## Troubleshooting

**Devices showing as "Disconnected":**
1. Confirm the remote device can reach port 22000 on the server
2. Check `docker logs syncthing` for connection errors
3. If devices are on different networks, ensure Tailscale or port forwarding is in place

**Files not syncing:**
- Check the folder status in the UI — it will show specific conflict or permission errors
- Syncthing will never overwrite or delete without showing a conflict first

**Out of sync indicator but nothing changes:**
- Check for conflicted copies in the folder — Syncthing creates `.sync-conflict` files instead of overwriting when both sides have changed
