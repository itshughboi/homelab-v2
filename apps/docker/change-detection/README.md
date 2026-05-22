1. After standing up compose, go to Settings -> Notifications and I can add my notification endpoints through the apprise format:
2. gotifys://gotify.hughboi.cc/TOKEN?priority=high
3. ntfys://ntfy.hughboi.cc/topic
4. https://discord.com/webhook

---

# changedetection.io

**URL:** https://change.hughboi.cc
**Docs:** https://changedetection.io/

Website change monitor. Watch URLs and get notified when the content changes. Used for tracking price changes, availability, service status pages, and any page that doesn't have an RSS feed.

## Stack

Two containers:

| Container | Image | Role |
|---|---|---|
| `change-detection` | `ghcr.io/dgtlmoon/changedetection.io` | Main app + scheduler |
| `change-detect-chrome` | `browserless/chrome` | Headless Chrome for JavaScript-heavy pages |

Chrome needs internet access to load and screenshot pages. The `changedetection` network is not `internal` for this reason.

## Volumes

| Host Path | Container Path | Purpose |
|---|---|---|
| `/home/hughboi/data/change-detection` | `/datastore` | All watch configs, snapshots, history, and screenshots |

## Playwright / Chrome

For pages that require JavaScript rendering, changedetection.io connects to the Chrome container at `ws://playwright-chrome:3000`. Set the **Fetch** method to **Playwright ChromeHTML** in the watch settings for JS-heavy pages.

Chrome config in compose:
- Max 10 concurrent sessions
- Ad blocking enabled by default
- Stealth mode enabled (reduces bot detection)

## First Run

1. `docker compose up -d`
2. Navigate to https://change.hughboi.cc
3. Set a password under **Settings → Security** immediately (no auth by default)
4. Add your first URL to watch
5. Configure notifications (see above for apprise formats)

## Notification Examples

```
# ntfy
ntfys://ntfy.hughboi.cc/change-detection

# Discord
discord://webhook_id/webhook_token
```

## Upgrade Notes

- All watch data is in `/home/hughboi/data/change-detection`. Back it up before upgrading.
- The `browserless/chrome` image uses a `1-chrome-stable` tag (major version + stable Chrome channel) — it updates with Chrome releases automatically when you pull.

## Troubleshooting

**"Fetch failed" for JavaScript pages:**
- Confirm Chrome is running: `docker logs change-detect-chrome`
- Switch the watch's fetch mode to **Playwright ChromeHTML** in the watch settings
- Test Chrome directly: `docker exec change-detect-chrome curl -s http://localhost:3000/json/version`

**Notifications not arriving:**
- Test the apprise URL format in the notification settings using the **Send test notification** button
- Verify ntfy is reachable from inside the container
