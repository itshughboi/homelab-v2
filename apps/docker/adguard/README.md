# AdGuard Home + Unbound

> [!NOTE] Deployment paths
> This repo checkout is canonical — production runs the stack from
> `apps/docker/adguard/compose.yaml`. App code (compose + unbound configs) is
> git-tracked here; runtime data lives outside the repo under
> `/home/hughboi/data/adguard/`:
> - `conf/AdGuardHome.yaml` — AdGuard config (bind mount; holds the admin
>   login's bcrypt hash, so this path is not committed)
> - `work/` — AdGuard runtime working dir
> - `unbound/var/root.key` — unbound DNSSEC auto-trust-anchor (writable)
>
> Unbound's `unbound.conf`, `forward-records.conf`, and `root.hints` are mounted
> read-only from `./unbound/` in this repo. This Docker instance is still
> canonical today; a k3s AdGuard is planned but not yet live — see
> docs/6-docker/index.md.

> [!IMPORTANT] Unbound listens on port 5335, not 53
> `unbound.conf` sets `interface: 0.0.0.0@5335`, so unbound listens on **5335**
> *inside* the container. Two consequences that have bitten this stack:
> - **Host port mapping is `5335:5335`** (not `5335:53`). The old `5335:53`
>   mapped the host port to a dead container port — it only ever appeared to
>   work because AdGuard reaches unbound over the docker network
>   (`192.168.100.10#5335`), which bypasses the host mapping entirely.
> - **The healthcheck uses `drill` on port 5335.** The `mvance/unbound` image
>   ships `drill` (ldns), not `dig`, and querying port 53 hits nothing. The old
>   `dig ... -p 53` healthcheck could never pass, so the container sat
>   "unhealthy" indefinitely despite resolving fine.

> [!NOTE] DNS monitoring / alerting lives in Gatus
> The container healthcheck is only a local Docker/Portainer signal. Actual
> "notify me when DNS breaks" alerting is in Gatus (`apps/docker/gatus`), which
> runs scheduled `dns://` resolve checks against both the full AdGuard chain
> (`10.10.10.10:53`) and unbound directly (`10.10.10.10:5335`) and pushes to
> ntfy/Discord on failure. See the "DNS" group in gatus/config/config.yaml.

> [!NOTE] Deploy flow (GitOps)
> Changes are **commit → push to Gitea → deploy via Semaphore** (`sops-deploy`
> template), which git-pulls on the host and runs the compose with SOPS secrets
> injected. Editing files directly on the host without committing leaves the
> host tree dirty and makes the Semaphore `git pull` fail
> ("Local modifications exist in the destination"). Always commit + push first.

### Adguard Installation
1. Remove stub listener on linux host
```sh
sudo nano /etc/systemd/resolved.conf
```
```sh
#LLMNR=no
#Cache=no-negative
#CacheFromLocalhost=no
DNSStubListener=no
#DNSStubListenerExtra=3
#ReadEtcHosts=yes
```
^^ Uncomment DNSStubListener=yes & set the value to 'no'
```
sudo systemctl restart systemd-resolved
```

!! Unbound configs are now git-tracked in `./unbound/` and mounted read-only by
`compose.yaml` — no manual copying to a data dir is needed anymore. The three
files, and how they're used:
1. `unbound/unbound.conf` — always mounted (the main config).
2. `unbound/forward-records.conf` — only relevant IF USING DoT instead of
   root-hints. **REFERENCE ONLY. NOT USED in the current setup!**
3. `unbound/root.hints` — **MY GO TO. Root-server recursion, what's active now.**

(Only the writable runtime dir `var/` — holding the DNSSEC `root.key` — lives
outside the repo, under `/home/hughboi/data/adguard/unbound/var`.)


## Unbound
- Recursive & Caching DNS Server (better performance over using just Adguard -> Quad9)
1. Inside Adguard UI -> DNS Forwarder
- Set this to be the docker IP we created for unbound. In my example, I will use **192.168.100.10**
2. Test resolution again


### DoT (Optional)
> [!NOTE] Include forward-records.conf and comment out root-hints on unbound.conf
> DoT isn't possible with root server, so need to disable it (commentroot-hints: "/opt/unbound/etc/unbound/root.hints") and uncomment (
    #include: /opt/unbound/etc/unbound/forward-records.conf)

- I have to pick between using DoT with forwarders to something like Quad9 or Cloudflare over port 853, or having Unbound query root servers directly, but that's all unencrypted plaintext (port 53).

If I want to do DoT, essentially I need to add a 'forward-records.conf' file where unbound has a volume mounted. Then in the unbound.conf comment the root hints, and uncomment the **include: "/opt/unbound/etc/unbound/forward-records.conf"**

*forward-records.conf*
```
forward-zone:
    # Forward all queries (except those in cache and local zone) to
    # upstream recursive servers
    name: "."
    # Queries to this forward zone use TLS
    forward-tls-upstream: yes

    # https://dnsprivacy.org/wiki/display/DP/DNS+Privacy+Test+Servers

    ## Cloudflare
    #forward-addr: 1.1.1.1@853#cloudflare-dns.com
    #forward-addr: 1.0.0.1@853#cloudflare-dns.com
    #forward-addr: 2606:4700:4700::1111@853#cloudflare-dns.com
    #forward-addr: 2606:4700:4700::1001@853#cloudflare-dns.com

    ## Cloudflare Malware
    # forward-addr: 1.1.1.2@853#security.cloudflare-dns.com
    # forward-addr: 1.0.0.2@853#security.cloudflare-dns.com
    # forward-addr: 2606:4700:4700::1112@853#security.cloudflare-dns.com
    # forward-addr: 2606:4700:4700::1002@853#security.cloudflare-dns.com

    ## Quad9
    forward-addr: 9.9.9.9@853#dns.quad9.net
    forward-addr: 149.112.112.112@853#dns.quad9.net
    forward-addr: 2620:fe::fe@853#dns.quad9.net
    forward-addr: 2620:fe::9@853#dns.quad9.net

```

TL;DR
- only using root.hints and unbound.conf with no forwarding to anything in forward-records.conf and no DoT because I'm querying root servers directly



#### Update Root.Hints
- Update every few months << figure out how to get n8n to automate this



### TO document
1. how to getdnssec working with the key files << how to generate
2. figure out if i should move or set more permissive things on the unbound.log that is getting snatched by promtail
3. play around with adguard log levels for loki
4. automate root.hints update with n8n or ansible
5. ~~how to have these ci/cd oriented and then apply to container so i can push changes, commit, apply, rebuild.~~ DONE — commit + push to Gitea, then Semaphore `sops-deploy` pulls on the host and redeploys (see the "Deploy flow" note at the top).
6. lock down key files for bind9 to least access
7. update my records
8. Automate root hints file every few months or so