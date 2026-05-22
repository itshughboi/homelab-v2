# FreshRSS

**URL:** https://freshrss.hughboi.cc
**Docs:** https://freshrss.github.io/FreshRSS/

Self-hosted RSS/Atom feed aggregator. Used to follow blogs, news, and any site that publishes a feed without needing a third-party reader service.

## Stack

Single container (LinuxServer image). Runs as `PUID=1000 / PGID=1000`.

## Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `/home/hughboi/data/rss` | `/config` | All FreshRSS data — feeds, articles, users, extensions, config |

## First Run

1. Navigate to https://freshrss.hughboi.cc
2. Complete the web installer: set language, database (use SQLite for simplicity), and create the admin account
3. Add feeds via the **+** button or import an OPML file under **Subscription management → Import/Export**

## Fever API (for third-party apps)

FreshRSS supports the Fever API for use with mobile clients like Reeder, NetNewsWire, or Unread.

1. Go to **Profile → API management**
2. Enable the Fever-compatible API
3. Set an API password (different from your login password)
4. API endpoint: `https://freshrss.hughboi.cc/api/fever.php`

## Google Reader API

Also supported for apps that use the GReader protocol:
- Endpoint: `https://freshrss.hughboi.cc/api/greader.php`
- Credentials: FreshRSS username + the API password set above

## Upgrade Notes

- All data is in `/home/hughboi/data/rss` on the host. Back this directory up before major version upgrades.
- LinuxServer images follow a rolling tag — check [LinuxServer releases](https://github.com/linuxserver/docker-freshrss/releases) for changelogs before bumping the version in compose.

## Troubleshooting

**Feeds not updating automatically:**
- FreshRSS uses a cron job inside the container for auto-refresh. Check `docker logs freshrss` for cron output.
- Default auto-refresh interval is configurable under **Administration → System configuration → Automatic feed refresh**.

**Can't log in after upgrade:**
- Check the container logs. LinuxServer images sometimes need a permission fix: `sudo chown -R 1000:1000 /home/hughboi/data/rss`
