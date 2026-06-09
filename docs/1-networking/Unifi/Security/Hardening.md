## Encrypted DNS

Two separate settings, two separate scopes:

**Client traffic — CyberSecure → Encrypted DNS**

Intercepts outbound DNS from clients and proxies it through DoH/DoT to the chosen provider (Cloudflare, Quad9, etc.). This is what makes client queries encrypted. Has no effect on the gateway's own DNS.

> [!NOTE]
> In this setup, client DNS already points at Bind9 (10.10.10.8) → AdGuard → Unbound → Quad9. CyberSecure Encrypted DNS would bypass that entire chain. Only enable it on networks not using internal DNS (e.g. Guest, IoT).

**Gateway's own resolver — Settings → Internet → DNS**

Controls DNS for the UXG Max itself (system updates, controller calls). Accepts IPv4 only — no DoH support in the UI. Set to Auto (ISP DHCP) or a public IPv4 like `9.9.9.9`. There is no native way to make the gateway's own resolver use DoH without CLI configuration.

The higher-impact config is Bind9 forwarding upstream via Quad9 — see [Networks/DNS.md](../Networks/DNS.md).

---

## TLS Certificate for the Local Controller

Primary access is via `https://unifi.hughboi.cc` (Traefik + Let's Encrypt) — no cert issues when Traefik is up.

If Traefik is unavailable, fall back to `https://10.10.10.10:8443` directly. This hits the controller's self-signed cert and will show a browser warning. Accepting the browser exception is fine as a break-glass fallback. If you want clean direct access without warnings, set up a local CA → issue a cert for the controller → install only the CA cert on your Mac (not the controller cert itself — it changes on reinstall).

