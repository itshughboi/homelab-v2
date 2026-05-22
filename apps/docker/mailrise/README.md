### Receive emails
- Mailrise uses the default domain mailrise.xyz. The email I need to send to depends on what mailrise.conf is setup as. Because I setup my notifications under 'Notify' field, the email I need to point everything to is **notify@mailrise.xyz**

---

# Mailrise

**URL:** https://mailrise.hughboi.cc (not really used — SMTP is how you interact with it)
**Port:** `8025` (SMTP — open to LAN on all interfaces)
**Docs:** https://github.com/YoRyan/mailrise

SMTP gateway that converts incoming emails into Apprise notifications. Any device or service that can send an email can use Mailrise to trigger push notifications to Discord, ntfy, Slack, etc. without needing API keys on the sending device.

## How It Works

1. A device/service sends an email to `notify@mailrise.xyz` on port `8025`
2. Mailrise receives it over SMTP
3. Mailrise looks up the notification config in `mailrise.conf` for that recipient
4. Sends the notification via Apprise (Discord, ntfy, etc.)

## Config

Config lives at `./mailrise.conf` (mounted `:ro`). Example structure:
```yaml
configs:
  notify:
    urls:
      - ntfys://ntfy.hughboi.cc/homelab
      - discord://webhook_id/webhook_token
```

Restart mailrise after changing the config: `docker restart mailrise`

## Apprise URL Formats

| Service | Format |
|---|---|
| ntfy (HTTPS) | `ntfys://ntfy.hughboi.cc/topic` |
| Discord | `discord://webhook_id/webhook_token` |
| Gotify (HTTPS) | `gotifys://gotify.hughboi.cc/TOKEN` |
| Slack | `slack://tokenA/tokenB/tokenC` |

Full list: https://github.com/caronc/apprise#supported-notifications

## Volumes

| Mount | Container Path | Purpose |
|---|---|---|
| `./mailrise.conf` | `/etc/mailrise.conf:ro` | Notification routing config |

## Devices That Use Mailrise

- Network printers / scanners → scan to email
- UPS / NAS devices with email alerting (SMTP configured to point to `10.10.10.10:8025`)
- Proxmox cluster (email alerts)
- Any legacy device that only supports email notifications

## SMTP Client Config (for devices)

| Setting | Value |
|---|---|
| SMTP Server | `10.10.10.10` |
| Port | `8025` |
| TLS | No (plain SMTP) |
| Authentication | None |
| From | Anything |
| To | `notify@mailrise.xyz` |

## Upgrade Notes

- No persistent data — config is in the repo. Upgrade is a tag bump + restart.
- Apprise dependency versions are bundled in the image. Check the [Mailrise releases](https://github.com/YoRyan/mailrise/releases) if a notification service format has changed.
