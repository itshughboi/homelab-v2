# Wazuh — Ingesting UniFi Syslog

How to get the UniFi gateway's syslog into Wazuh. The UniFi side (what to send, log
levels, sampling) is documented in
[1-networking/.../Logging.md](../1-networking/Unifi/Security/Logging.md); this is the
**receiving** side.

> Deployment: Wazuh 4.12 single-node Docker stack on **dock-prod (10.10.10.10)** —
> `apps/docker/wazuh/`. Dashboard at `https://wazuh.hughboi.cc` (via Traefik). **Docker is
> current production.** A future k3s variant is covered in
> [Running on k3s](#running-on-k3s-future) — the Wazuh config is identical there, only the
> packaging and UDP ingress differ.

---

## The gap to close first

The compose file publishes `514:514/udp` on the manager, **but the manager is not yet
configured to accept syslog.** `wazuh_manager.conf` only has the agent `<remote>` block:

```xml
<remote>
  <connection>secure</connection>   <!-- this is for Wazuh AGENTS, port 1514/tcp -->
  <port>1514</port>
  <protocol>tcp</protocol>
</remote>
```

Without a **syslog** remote block, UniFi packets arriving on 514/udp are dropped. UniFi is
not a Wazuh agent — it can only forward raw syslog, so the manager has to be told to listen
for it.

---

## 1. Add the syslog remote block

Edit `apps/docker/wazuh/config/wazuh_cluster/wazuh_manager.conf` (deployed on dock-prod at
`${CODE_ROOT}/wazuh/config/wazuh_cluster/wazuh_manager.conf`, mounted to the container's
`ossec.conf`). Add a second `<remote>` block alongside the existing agent one:

```xml
<remote>
  <connection>syslog</connection>
  <port>514</port>
  <protocol>udp</protocol>
  <!-- Only accept syslog from the management subnet. Narrow to 10.10.10.254 if the
       UXG Max gateway is the only forwarder; widen to the subnet if adopted APs/switches
       also send from their own IPs. -->
  <allowed-ips>10.10.10.0/24</allowed-ips>
  <local_ip>0.0.0.0</local_ip>
</remote>
```

Restart the manager:

```sh
# on dock-prod, from the wazuh compose dir
docker compose restart wazuh.manager
```

> [!NOTE] Where the packets actually land
> UniFi forwards to `wazuh.hughboi.cc:514`. That hostname resolves to dock-prod
> (10.10.10.10), where `514/udp` is published straight to the manager container — it does
> **not** go through Traefik (Traefik only handles the HTTPS dashboard on 443). So the same
> hostname serves the dashboard over HTTPS *and* raw syslog over UDP, both because it
> resolves to dock-prod.

---

## 2. Confirm packets are arriving

Before worrying about parsing, prove the syslog is hitting the box:

```sh
# On dock-prod — watch for UniFi syslog on the wire
sudo tcpdump -n -i any udp port 514

# Then, to confirm Wazuh is reading them, temporarily enable raw logging:
#   in wazuh_manager.conf <global>:  <logall>yes</logall>
# restart the manager, then tail:
docker exec wazuh_manager tail -f /var/ossec/logs/archives/archives.log
```

You should see UniFi lines (firewall blocks, DHCP, admin logins, etc.). **Turn `logall`
back off** afterward — it writes every event to disk and grows fast.

---

## 3. Parsing — decoders and rules

Wazuh's built-in ruleset has generic firewall/syslog decoders, but **no UniFi-specific
decoder**. UniFi log formats also vary by firmware. So expect raw ingestion to work
immediately, but clean field extraction (src IP, action, rule name) needs a custom decoder
tuned to *your* actual log lines.

User-defined decoders/rules live in the container at `/var/ossec/etc/decoders/` and
`/var/ossec/etc/rules/` (the `wazuh_etc` volume), already wired in `wazuh_manager.conf`:

```xml
<decoder_dir>etc/decoders</decoder_dir>
<rule_dir>etc/rules</rule_dir>
```

**Workflow:**

1. Grab a few real UniFi lines from `archives.log` (step 2).
2. Test parsing interactively — paste a line into the logtest tool:
   ```sh
   docker exec -it wazuh_manager /var/ossec/bin/wazuh-logtest
   ```
3. Write a starter decoder at `/var/ossec/etc/decoders/unifi_decoders.xml`, e.g.:
   ```xml
   <decoder name="unifi">
     <program_name>^kernel|^hostapd|^dnsmasq</program_name>
   </decoder>

   <decoder name="unifi-fw">
     <parent>unifi</parent>
     <prematch>\[FW\.</prematch>
     <regex>SRC=(\S+) DST=(\S+).+PROTO=(\S+)</regex>
     <order>srcip,dstip,protocol</order>
   </decoder>
   ```
   > The regex above is a **starting point** — adjust the `prematch`/`regex` to match the
   > exact strings your firmware emits (confirmed via `wazuh-logtest`). Don't assume it
   > matches as-is.
4. Add rules at `/var/ossec/etc/rules/unifi_rules.xml` to alert on what matters, e.g. a
   firewall drop from a WAN source, repeated admin login failures, etc.
5. Restart the manager and re-test with `wazuh-logtest`.

---

## 4. View in the dashboard

`https://wazuh.hughboi.cc` → Discover / Threat Hunting. Filter incoming UniFi events by
`location: /var/ossec/logs/...` or the decoder/rule you created. Once a custom rule fires,
events show up under Security Alerts and feed correlation.

---

## Running on k3s (future)

> Docker on dock-prod is the current production deployment (everything above). This is the
> migration target. The Wazuh **config** — the syslog `<remote>` block, `allowed-ips`, the
> decoders and rules — is **identical**; only the packaging and the way external UDP 514
> reaches the manager change.

The one real difference is **L4 ingress**: syslog is raw UDP and cannot go through Traefik
(HTTP only), so the manager pod needs a stable layer-4 entry point.

**1. Expose UDP 514 with a MetalLB LoadBalancer Service:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: wazuh-syslog
  namespace: wazuh
  annotations:
    metallb.universe.tf/loadBalancerIPs: 10.10.30.68   # a free IP in the MetalLB pool (.60–.99); not .75 traefik / .65 adguard
spec:
  type: LoadBalancer
  externalTrafficPolicy: Local        # preserve UniFi's real source IP
  selector:
    app: wazuh-manager
  ports:
    - name: syslog-udp
      protocol: UDP
      port: 514
      targetPort: 514
```

Point UniFi's syslog destination at that LB IP (or a DNS name resolving to it).
`externalTrafficPolicy: Local` is **required** — without it kube-proxy SNATs the packet to a
node IP, which breaks the `<allowed-ips>` filter (and any per-source rules), since Wazuh
would then see every event as coming from a cluster node.

**2. Manager config via ConfigMap.** The same `<remote><connection>syslog</connection>…`
block goes into the ConfigMap backing `/wazuh-config-mount/etc/ossec.conf`. Custom decoders/
rules mount as ConfigMaps to `/var/ossec/etc/decoders/` and `/var/ossec/etc/rules/` (or bake
them into a custom image).

**3. Persistence.** The Docker named volumes become Longhorn PVCs (manager `etc/`, `logs/`,
`queue/`; indexer data).

**4. Verify** the same way, via `kubectl`:

```sh
kubectl -n wazuh exec -it deploy/wazuh-manager -- /var/ossec/bin/wazuh-logtest
kubectl -n wazuh exec -it deploy/wazuh-manager -- tail -f /var/ossec/logs/archives/archives.log
```

Everything else (the block content, verification, decoder workflow) is unchanged from the
Docker section.

---

## Related

- UniFi-side syslog config (levels, what to forward): [Logging.md](../1-networking/Unifi/Security/Logging.md)
- Auto-blocking malicious IPs at the firewall: [CrowdSec-UniFi-Bouncer.md](CrowdSec-UniFi-Bouncer.md)
- Wazuh deployment/runbook: `apps/docker/wazuh/README.md`
