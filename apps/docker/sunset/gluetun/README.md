# Gluetun (sunset)

VPN gateway container (Mullvad, WireGuard) — originally paired with `soularr`
for torrent traffic, and briefly considered for an audio-automation pipeline
(torrent-based music acquisition routed through the VPN, served via
Navidrome) that never ended up getting built.

Deleted from the repo 2026-07 as a byte-identical duplicate of
`apps/docker/sunset/soularr/compose.yaml`'s own gluetun config — soularr is
the tracked copy going forward. The original compose.yaml (with the
navidrome pairing) is preserved in git history at commit `f0ad719`.

**Status:** sunset, not deployed from the repo. A real `gluetun` container
still exists on dock-prod (crashed, `exited - code 1` as of 2026-07-17) —
that's a leftover from the original manual setup, not something the repo
ever drove. Safe to remove from dock-prod; nothing here needs it to stay
running.

**If revisited for audio automation later:** the original config used
Mullvad WireGuard, `NET_ADMIN` + `/dev/net/tun`, and a shared `torrent`/`vpn`
network with `soularr`. Retrieve the full original compose.yaml with:

```sh
git show f0ad719:apps/docker/sunset/gluetun/compose.yaml
```
