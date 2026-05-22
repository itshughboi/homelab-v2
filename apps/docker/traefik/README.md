Make sure to give acme.json 600 permissions

---

# Traefik

**URL:** https://traefik.hughboi.cc (dashboard, basic auth protected)
**Docs:** https://doc.traefik.io/traefik/

Reverse proxy and TLS termination for all homelab services. Every service that needs HTTPS goes through Traefik. Traefik reads Docker labels from containers and automatically creates routes.

## Stack

Single container. Mounts:
- `docker.sock:ro` — to discover containers and read their labels
- `acme.json` — Let's Encrypt certificate storage (must be `chmod 600`)
- `traefik.yml` and `config.yml` — static and dynamic config (both `:ro`)
- `/var/log/traefik` — access and error logs (CrowdSec reads these)

## TLS

All certificates are issued via Cloudflare DNS challenge (no port 80 required for cert issuance). The Cloudflare API token is passed as a Docker secret from `/home/hughboi/data/traefik/cf_api_token.txt`.

```sh
# The token file must exist before starting Traefik
echo "YOUR_CF_TOKEN" > /home/hughboi/data/traefik/cf_api_token.txt
chmod 600 /home/hughboi/data/traefik/cf_api_token.txt
```

Wildcard cert covers `*.hughboi.cc`:
```yaml
tls:
  domains[0].main: hughboi.cc
  domains[0].sans: "*.hughboi.cc"
```

## Ports

| Port | Purpose |
|---|---|
| `80` | HTTP — all traffic redirected to HTTPS |
| `443` | HTTPS |

## Dashboard Access

The dashboard is at https://traefik.hughboi.cc behind HTTP basic auth. Credentials are set via `TRAEFIK_DASHBOARD_CREDENTIALS` in `.env` (htpasswd format). Generate with:
```sh
echo $(htpasswd -nb username password) | sed -e 's/\$/\$\$/g'
```
Double the `$` signs because Docker Compose interpolates `$`.

## Adding a New Service

Add these labels to any service container to expose it via Traefik:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.entrypoints=http"
  - "traefik.http.routers.myapp.rule=Host(`myapp.hughboi.cc`)"
  - "traefik.http.middlewares.myapp-https-redirect.redirectscheme.scheme=https"
  - "traefik.http.routers.myapp.middlewares=myapp-https-redirect"
  - "traefik.http.routers.myapp-secure.entrypoints=https"
  - "traefik.http.routers.myapp-secure.rule=Host(`myapp.hughboi.cc`)"
  - "traefik.http.routers.myapp-secure.tls=true"
  - "traefik.http.routers.myapp-secure.tls.certresolver=cloudflare"
  - "traefik.http.services.myapp.loadbalancer.server.port=8080"
  - "traefik.docker.network=proxy"
```
Also join the `proxy` network in the service's networks section.

## CrowdSec Integration

CrowdSec reads Traefik access logs from `/home/hughboi/data/traefik/logs/`. The bouncer adds a `crowdsec-bouncer` middleware. See [../crowdsec/README.md](../crowdsec/README.md) for setup.

To apply CrowdSec to all routes, add the middleware to each router or set it globally in `config.yml`:
```yaml
http:
  middlewares:
    crowdsec-bouncer:
      forwardAuth:
        address: http://bouncer-traefik:8080/api/v1/forwardAuth
        trustForwardHeader: true
```

## Upgrade Notes

- `acme.json` stores all TLS certificates. Back it up — losing it means re-issuing all certs.
- Check [Traefik migration docs](https://doc.traefik.io/traefik/migration/v2-to-v3/) when crossing major versions (v2 → v3 had label format changes).
- After upgrading, verify the dashboard loads and a few services are reachable before considering the upgrade successful.

## Troubleshooting

**Service returns "404 Not Found" from Traefik:**
- Check that the container is on the `proxy` network: `docker network inspect proxy | grep container_name`
- Verify the `traefik.enable=true` label is set
- Check router rules in the Traefik dashboard under **HTTP → Routers**

**TLS certificate not issuing:**
- Check `docker logs traefik` for ACME errors
- Verify the CF API token has `Zone:DNS:Edit` permission for the `hughboi.cc` zone
- `acme.json` must be `chmod 600` or Traefik will refuse to write to it

**Dashboard returning 401:**
- Regenerate credentials with `htpasswd` and make sure `$` signs are doubled in the env var