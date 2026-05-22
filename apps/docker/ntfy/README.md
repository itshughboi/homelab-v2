# ntfy

**URL:** https://ntfy.hughboi.cc
**Docs:** https://docs.ntfy.sh/

Self-hosted push notification server. Used as the central notification hub for the entire homelab — alerts from Diun, Semaphore, n8n, Vaultwarden backups, Wazuh, and anything else that supports ntfy or HTTP webhooks.

## Stack

Single container.

## Config

The server config is at `./server.yml` in the service directory, mounted at `/etc/ntfy/server.yml:ro`.

Key settings to configure in `server.yml`:
```yaml
base-url: https://ntfy.hughboi.cc
listen-http: :80
cache-file: /var/cache/ntfy/cache.db
cache-duration: 12h
auth-file: /var/cache/ntfy/auth.db
auth-default-access: deny-all   # require auth on all topics
behind-proxy: true
```

## Volumes

| Mount | Purpose |
|---|---|
| `cache` (named volume) | Message cache DB and auth DB |
| `./server.yml:/etc/ntfy/server.yml:ro` | Server configuration |

## Topics in Use

| Topic | Sender |
|---|---|
| `diun` | Docker image update notifications |
| `semaphore` | Ansible playbook results |
| `vaultwarden` | Backup success/failure |
| `homelab` | General homelab alerts |

## Subscribing on Mobile

Install the ntfy app ([Android](https://play.google.com/store/apps/details?id=io.heckel.ntfy) / [iOS](https://apps.apple.com/app/ntfy/id1625396347)):

1. Open the app → **+** → **Custom server** → `https://ntfy.hughboi.cc`
2. Subscribe to topics (e.g. `diun`, `semaphore`)
3. If auth is enabled, enter credentials

## Sending a Test Notification

```sh
curl -d "Test message" https://ntfy.hughboi.cc/homelab
# With auth:
curl -u "username:password" -d "Test message" https://ntfy.hughboi.cc/homelab
```

## Auth / Access Control

To add users (from inside the container):
```sh
docker exec -it ntfy ntfy user add --role=admin hughboi
docker exec -it ntfy ntfy user add --role=user myapp
docker exec -it ntfy ntfy access myapp homelab rw   # grant myapp read+write on 'homelab'
```

## Upgrade Notes

- The `cache` named volume holds both the message cache and the user auth database. Back it up before upgrading.
- Check the [ntfy changelog](https://github.com/binwiederhier/ntfy/releases) for config format changes between versions.

## Troubleshooting

**Mobile app not receiving notifications:**
1. Confirm the topic name is correct (case-sensitive)
2. Check `docker logs ntfy` for delivery errors
3. If using auth, verify the app is configured with valid credentials

**Notifications arriving with delay:**
- ntfy uses long-polling. If behind a proxy, ensure `behind-proxy: true` is set in `server.yml` and that Traefik isn't buffering connections.
