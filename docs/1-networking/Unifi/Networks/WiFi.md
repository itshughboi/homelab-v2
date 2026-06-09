## Channel AI

Settings → WiFi → Radio Manager → Channel AI

**Enable it.** Automatically selects optimal channels and adjusts TX power based on RF environment. Reduces interference and eliminates manual channel tuning. Runs periodically in the background — changes are applied during low-traffic windows.

---

## WiFiman Support

Settings → WiFi → WiFiman

**Enable it.** Allows the WiFiman app (iOS/Android) to discover this network for:
- WAN speed tests from the gateway
- Ping and traceroute tests
- WiFi signal analysis and channel scanning

Zero overhead. No reason to leave it off.

---

## Guest Network — Speed Limit

Settings → WiFi → `hughboi-guest` → Advanced → WiFi Speed Limit (Create or select new `guest` profile and cap UPLOAD)

**Enable per-client rate limiting.** Without it a single guest can saturate your WAN uplink.

| Direction | Recommended limit |
| --- | --- |
| Download | 50 Mbps |
| Upload | 25 Mbps |

Adjust based on your WAN speed. The goal is preventing a single guest from hogging the pipe, not degrading normal browsing.

Guest SSID is bound to VLAN — see [README.md](README.md). Client isolation is enabled; guests cannot see each other or any internal hosts.
