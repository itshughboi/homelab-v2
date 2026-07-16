## Overview
- Crowdsec is essentially a social network firewall. It does everything that fail2ban does, but crowdsec also can preemptively ban bad IP's that are put into the crowd defense. Essentially it's fail2ban Premium. Having both is redunant and can cause issues by being double banned with different rules. Fail2ban also gets installed on the host which adds *state* whereas with crowdsec that runs in container and is *stateless*

## ⚠️ CrowdSec is a hard dependency for ALL Traefik traffic — never stop it alone

Traefik applies the `crowdsec-bouncer` forwardAuth middleware **globally**, to every entrypoint
(`apps/docker/traefik/data/traefik.yml`). ForwardAuth fails **closed**: if `bouncer-traefik`
isn't reachable, every request through Traefik gets a `403`, homelab-wide — not just this
service. That includes Gitea and Semaphore, the tools you'd need to fix it.

This bit us during the SOPS migration: stopping `bouncer-traefik` to prepare a cutover to the
repo's compose file took down the entire homelab's ingress, including access to Semaphore/Gitea
themselves. Recovered by bringing the **old** compose file (`/home/hughboi/crowdsec/`, still
intact on disk) back up manually.

**Migration status:** `compose.yaml` in this directory is already updated (named volumes
`crowdsec-config`/`crowdsec-db` instead of stale host paths — see git history) and pushed, but
the actual cutover from the old deployment is **deliberately deferred** until there's an atomic,
no-gap plan (e.g. a single Ansible play that brings the new stack up *before* tearing the old one
down, rather than manual stop-then-start). Don't `docker stop`/`docker rm` the live `crowdsec` or
`bouncer-traefik` containers without a replacement already running and verified.

**The bouncer API key is generated, not migrated.** Unlike other services' secrets, there's no
pre-existing key to encrypt — it's created by running `cscli bouncers add bouncer-traefik` inside
the container *after* it's already running (see Installation below). The repo's `.env.sops`
currently holds a placeholder value for this reason; a real cutover needs: bring up `crowdsec`
alone → generate the real key → encrypt it → bring up `bouncer-traefik` with the real key. Losing
the old ban list/machine registration is acceptable (confirmed with the user — CrowdSec here is
internal-only), so a clean reset is fine; just never leave Traefik without a *running* bouncer.


## Installation
1. Configure Traefik. <br>
    a. Add crowdsec middleware
    ```
      http:
        middlewares:    
            crowdsec-bouncer:
            forwardauth:
                address: http://bouncer-traefik:8080/api/v1/forwardAuth
                trustForwardHeader: true     
    ```
    b. Add this to traefik.yml
    ```
    log:
      level: "INFO"
      filePath: "/var/log/traefik/traefik.log"
    accessLog:
      filePath: "/var/log/traefik/access.log"
    ```
    c. Restart traefik
2. Start docker compose
3. Go into crowdsec container to create API key
```sudo docker exec crowdsec cscli bouncers add bouncer-traefik```
4. Put API Key into .env
5. Restart container
