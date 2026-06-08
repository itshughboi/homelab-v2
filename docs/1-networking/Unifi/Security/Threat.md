## Intrusion Prevention (IPS)

Settings → Security → Intrusion Prevention

- Enable on **all networks** — the UXG Max has headroom for it and you can't predict which VLAN gets hit first
- **Start in Notify mode for 3–5 days** to surface false positives, then switch to **Block**
- Do not leave on Notify permanently — notify-only = IDS (watches, doesn't act). Block = IPS (actually stops traffic)
- Threat detection mode: **Notify + Block** once tuning period is done

---

## Region Blocking

Settings → Security → Country Blocking

- Enable for **inbound WAN traffic only**
- Block regions you'll never receive legitimate connections from (common: CN, RU, KP, IR, BY)
- **Do not enable for outbound** — CDNs (Cloudflare, Akamai) route through servers worldwide; enabling outbound region blocking will silently break streaming, package downloads, and games

---

## Honeypot

Settings → Security → Honeypot

- Deploy on an **unused IP in the Management VLAN** (pick one outside the DHCP range and not reserved for anything)
- Any connection to it = something scanning internally that shouldn't be: compromised IoT device, lateral movement, misconfigured service
- Zero ongoing overhead, high signal-to-noise ratio
- Alert will appear in UniFi Threat Management and syslog → Wazuh will pick it up if syslog forwarding is configured

---

## Rogue DHCP Server Detection

Settings → Security → Network Security → Rogue DHCP Detection (or per-network Advanced settings)

**Enable it.** Alerts when an unauthorized DHCP server responds on any network. Catches:
- Misconfigured VM handing out IPs
- Someone plugging a home router into a switch port
- Compromised IoT device acting as a DHCP server
- Misconfigured container with a DHCP server exposed

Low overhead, no false-positive risk in a well-controlled environment. Any alert here warrants immediate investigation.

---

## Default Security Posture

Settings → Security → Threat Management → Security Posture

This controls IPS/Threat Management sensitivity — **not** the firewall default action (that's handled by zone rules).

- **Allow All** = IPS in detect-only mode. Same as Notify. Threats are logged but not stopped.
- **Block** = IPS actively drops flagged traffic.

Current: Allow All. **Change to Block after the 3–5 day Notify tuning period.**

> [!NOTE]
> This setting does not override your zone-based firewall rules. It only governs the
> IPS/Threat engine's response to traffic it flags as malicious.
