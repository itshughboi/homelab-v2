# CrowdSec — UniFi Bouncer (firewall auto-block)

Adds network-layer auto-blocking: CrowdSec decisions get pushed into a UniFi firewall group
+ drop rule, so a banned IP is blocked at the **gateway** for every protocol — not just HTTP.

> Deployment: CrowdSec v1.7.8 Docker on **dock-prod** — `apps/docker/crowdsec/`. **Docker is
> current production.** A future k3s variant is covered in
> [Running on k3s](#running-on-k3s-future); the decision/enforcement model is identical, only
> the packaging changes.

---

## What you have vs. what this adds

Today CrowdSec runs with **one bouncer — the Traefik bouncer** (`bouncer-traefik`). It
enforces at the reverse proxy, so it only blocks traffic that *goes through Traefik* (HTTP/
HTTPS vhosts). CrowdSec's decisions come from its parsers:

- `crowdsecurity/traefik` → reads `/var/log/traefik/*` (acquis.yaml)
- `crowdsecurity/linux` → SSH/auth patterns

A **UniFi bouncer** registers as a second bouncer against the same CrowdSec LAPI and reads
the *same* decision list. The difference is enforcement point:

| Bouncer | Enforces at | Blocks | Best for |
| --- | --- | --- | --- |
| Traefik (current) | Reverse proxy | HTTP/HTTPS only | Web apps behind Traefik |
| UniFi (this doc) | Gateway firewall | All protocols/ports | WAN-facing / port-forwarded / non-HTTP (e.g. SSH, WireGuard) |

They complement each other — one decision, blocked at both layers.

> [!NOTE] No official first-party UniFi bouncer
> CrowdSec ships first-party bouncers for nftables, iptables, nginx, traefik, cloudflare,
> etc. — **not** UniFi. The practical option is the community
> [`teifun2/crowdsec-unifi-bouncer`](https://github.com/teifun2/crowdsec-unifi-bouncer),
> which talks to the UniFi controller API, maintains an address group, and applies a drop
> rule. Treat the env-var names below as representative — **verify against the project's
> current README**, as community bouncers change.

---

## 1. Register the bouncer with CrowdSec

Generate an API key from the running CrowdSec container:

```sh
docker exec crowdsec cscli bouncers add unifi-bouncer
```

Copy the key it prints (shown once). This is the `CROWDSEC_LAPI_KEY` below.

---

## 2. Create a UniFi account for the bouncer

The bouncer needs to log into the controller (UniFi Network on dock-prod,
`https://10.10.10.10:8443`) to manage the firewall group/rule.

- Use a **dedicated local admin** account (not the cloud/`ui.com` account — cloud accounts
  don't work for API automation, same constraint as the Ansible admin noted in
  [Switch_Port_Assignments.md](../1-networking/Unifi/Assignments/Switch_Port_Assignments.md)).
- Store the credentials in Vaultwarden.

---

## 3. Run the bouncer container

Because the bouncer must reach CrowdSec's LAPI at `crowdsec:8080`, put it on the same
`proxy` network. Representative compose (add to `apps/docker/crowdsec/compose.yaml` — verify
keys against the project README):

```yaml
  bouncer-unifi:
    container_name: bouncer-unifi
    image: ghcr.io/teifun2/crowdsec-unifi-bouncer:latest
    restart: unless-stopped
    depends_on:
      crowdsec:
        condition: service_started
    environment:
      - CROWDSEC_BOUNCER_API_KEY=${CROWDSEC_UNIFI_API_KEY}
      - CROWDSEC_URL=http://crowdsec:8080
      - UNIFI_HOST=https://10.10.10.10:8443
      - UNIFI_USER=${UNIFI_BOUNCER_USER}
      - UNIFI_PASS=${UNIFI_BOUNCER_PASS}
      - UNIFI_SITE=default
      - UNIFI_SKIP_TLS_VERIFY=true   # self-signed controller cert
    networks:
      - proxy
```

Add the three new secrets to `apps/docker/crowdsec/.env` (key from step 1, UniFi creds from
step 2), then `docker compose up -d`.

---

## 4. Confirm the UniFi firewall rule

On first run the bouncer creates a firewall **address group** (e.g. `crowdsec-blocklist`)
and a **drop rule** referencing it. Verify in UniFi:

- The group exists and populates as decisions accumulate.
- A firewall rule drops traffic from that group. Apply it where it matters — primarily
  **Internet/WAN-In** (block inbound from banned IPs to any port-forwarded service). Some
  bouncer versions create the rule for you; otherwise create it manually pointing at the
  group.

---

## 5. Test the full path

```sh
# Add a throwaway decision
docker exec crowdsec cscli decisions add --ip 203.0.113.66 --duration 5m --reason "test"

# Confirm CrowdSec holds it
docker exec crowdsec cscli decisions list

# Check the UniFi group now contains 203.0.113.66 (UniFi UI), then clean up
docker exec crowdsec cscli decisions delete --ip 203.0.113.66
```

If the IP appears in the UniFi group within the bouncer's sync interval and disappears after
delete, the loop works.

---

## Optional — feed UniFi/Wazuh events back into CrowdSec

CrowdSec's decisions come from its own parsers (traefik, linux), **not** from UniFi syslog.
To make a UniFi-detected event (e.g. a firewall block or repeated admin-login failure that
Wazuh sees) *also* produce a CrowdSec ban, bridge them with **Wazuh Active Response**:

- Wazuh's `<active-response>` block is currently commented out in `wazuh_manager.conf`, and
  the firewall-drop/host-deny commands are defined but unused.
- Wire an Active Response script that runs `cscli decisions add --ip <X>` (against the
  CrowdSec container) when a chosen Wazuh rule fires. That decision then propagates to both
  the Traefik and UniFi bouncers.

This is the dotted line in the pipeline diagram in
[Logging.md](../1-networking/Unifi/Security/Logging.md) — optional and custom, not required
for the core auto-block loop above.

---

## Running on k3s (future)

> Docker on dock-prod is current production (everything above). On migration, CrowdSec moves
> to the official Helm chart and the bouncers become Deployments. The decision/enforcement
> model is unchanged — one LAPI, decisions fan out to every registered bouncer.

- **CrowdSec** via the official `crowdsecurity/crowdsec` Helm chart — the LAPI becomes a
  ClusterIP Service (e.g. `crowdsec-service.crowdsec.svc:8080`).
- **UniFi bouncer** as a Deployment using the same community image, env sourced from a
  Secret. **Do not put the API key or UniFi creds in a manifest** — manage them with Sealed
  Secrets / SOPS per [Secrets_SOPS.md](../8-gitops/Secrets_SOPS.md).
- Register the bouncer key in-cluster:
  ```sh
  kubectl -n crowdsec exec deploy/crowdsec -- cscli bouncers add unifi-bouncer
  ```
- **Egress to the controller — the gotcha.** The UniFi Network controller stays on dock-prod
  (`10.10.10.10:8443`) even after CrowdSec moves to k3s, so the bouncer pod (VLAN 30) must
  reach MGMT (VLAN 10) on 8443. MGMT normally **denies** inbound from k3s
  ([firewall rules](../1-networking/Unifi/Firewall/Rules.md)), so this needs both a
  Kubernetes NetworkPolicy egress allow **and** a UniFi firewall rule permitting that
  specific k3s workload → `10.10.10.10:8443`. Scope it tightly to the bouncer, not all of k3s.
- Decisions still come from CrowdSec's own parsers (Traefik, Linux). In k3s the Traefik
  bouncer and the UniFi bouncer both read the same LAPI — **one decision, blocked at ingress
  AND at the gateway.**

---

## Related

- Pipeline overview + diagram: [Logging.md](../1-networking/Unifi/Security/Logging.md)
- Getting UniFi logs into Wazuh: [Wazuh-UniFi-Logs.md](Wazuh-UniFi-Logs.md)
- CrowdSec deployment/runbook: `apps/docker/crowdsec/README.md`
