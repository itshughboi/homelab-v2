# Authentik

Identity provider and SSO for the k3s stack. Replaces Pocket ID in Kubernetes (Pocket ID remains on Docker for its simpler UI).

## Overview

| | |
|---|---|
| **Image** | `ghcr.io/goauthentik/server:2024.12` |
| **Domain** | `authentik.hughboi.vip` |
| **Port** | 9000 (HTTP) |
| **Components** | server + worker + PostgreSQL + Redis |
| **Storage** | 10Gi (postgres) + 1Gi (redis) |

## Architecture

| Component | Role |
|-----------|------|
| `authentik-server` | API, web UI, embedded proxy |
| `authentik-worker` | Background tasks, flows, blueprints, certificate rotation |
| `authentik-postgres` | User/group/policy state |
| `authentik-redis` | Cache + task queue |

## Before You Apply

Create the secret:
```bash
# Generate a strong secret key first
python3 -c "import secrets; print(secrets.token_urlsafe(50))"

kubectl create secret generic authentik-env -n authentik \
  --from-literal=AUTHENTIK_SECRET_KEY=<generated-key> \
  --from-literal=AUTHENTIK_POSTGRESQL__PASSWORD=<db-password> \
  --from-literal=AUTHENTIK_EMAIL__HOST=smtp.example.com \
  --from-literal=AUTHENTIK_EMAIL__PORT=587 \
  --from-literal=AUTHENTIK_EMAIL__USERNAME=<smtp-user> \
  --from-literal=AUTHENTIK_EMAIL__PASSWORD=<smtp-password> \
  --from-literal=AUTHENTIK_EMAIL__FROM=authentik@hughboi.vip \
  --from-literal=POSTGRESQL_PASSWORD=<same-db-password>
```

> **AUTHENTIK_SECRET_KEY must never change** after first boot — it encrypts stored tokens, flow states, and OAuth client secrets. If it changes, all sessions are invalidated and stored secrets become unreadable.

## Deploy Order

```bash
kubectl apply -f namespace.yaml
kubectl apply -f postgres.yaml
kubectl apply -f redis.yaml
kubectl rollout status deployment/authentik-postgres -n authentik
kubectl rollout status deployment/authentik-redis -n authentik
kubectl apply -f server.yaml
kubectl apply -f worker.yaml
kubectl apply -f ingressroute.yaml
```

## First Boot

Navigate to `https://authentik.hughboi.vip/if/flow/initial-setup/` to create the default admin account.

## Protecting Apps with Authentik

Authentik integrates with Traefik via the **Forward Auth** pattern. Two steps per app:

### 1. Create an Authentik Provider + Application

In the Authentik UI:
- **Providers → Create → Proxy Provider**
  - Name: `app-name`
  - Mode: `Forward auth (single application)`
  - External host: `https://app.hughboi.vip`
- **Applications → Create**
  - Link to the provider above

### 2. Add ForwardAuth Middleware to Traefik

```yaml
# In your app's IngressRoute, add middlewares:
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: authentik-forward-auth
  namespace: authentik
spec:
  forwardAuth:
    address: http://authentik-server.authentik.svc.cluster.local:9000/outpost.goauthentik.io/auth/traefik
    trustForwardHeader: true
    authResponseHeaders:
      - X-authentik-username
      - X-authentik-groups
      - X-authentik-email
      - X-authentik-name
      - X-authentik-uid
      - X-authentik-jwt
      - X-authentik-meta-jwks
      - X-authentik-meta-outpost
      - X-authentik-meta-provider
      - X-authentik-meta-app
      - X-authentik-meta-version
```

Then in each app IngressRoute:
```yaml
routes:
  - match: Host(`app.hughboi.vip`)
    middlewares:
      - name: authentik-forward-auth
        namespace: authentik
```

### 3. Embedded Outpost (No Extra Pod Required)

Authentik ships an embedded outpost that handles forward auth without deploying a separate outpost pod. The address `authentik-server.authentik.svc.cluster.local:9000/outpost.goauthentik.io/auth/traefik` is served directly by the server component.

## OIDC / OAuth2 for Apps That Support It

For apps with built-in OIDC support (Grafana, Gitea, etc.):

1. **Providers → Create → OAuth2/OpenID Connect Provider**
   - Client type: Confidential
   - Redirect URIs: the app's callback URL
2. Note the **Client ID** and **Client Secret**
3. Configure the app to use:
   - **Issuer URL**: `https://authentik.hughboi.vip/application/o/<app-slug>/`
   - **Auth URL**: `https://authentik.hughboi.vip/application/o/authorize/`
   - **Token URL**: `https://authentik.hughboi.vip/application/o/token/`

### Grafana OIDC Example

Add to the Grafana Helm values in `monitoring/kube-prometheus-stack/values.yaml`:
```yaml
grafana:
  grafana.ini:
    auth.generic_oauth:
      enabled: true
      name: Authentik
      allow_sign_up: true
      client_id: <grafana-client-id>
      client_secret: <grafana-client-secret>
      scopes: openid email profile
      auth_url: https://authentik.hughboi.vip/application/o/authorize/
      token_url: https://authentik.hughboi.vip/application/o/token/
      api_url: https://authentik.hughboi.vip/application/o/userinfo/
      role_attribute_path: contains(groups, 'grafana-admins') && 'Admin' || 'Viewer'
```

### Gitea OIDC Example

In Gitea admin panel: **Site Administration → Authentication Sources → Add OAuth2**
- Provider: OpenID Connect
- Client ID/Secret: from Authentik provider
- OpenID Connect Auto Discovery URL: `https://authentik.hughboi.vip/application/o/<app-slug>/.well-known/openid-configuration`

## Notes

- Add `authentik` to the Reflector annotation on the TLS certificate.
- The server exposes Prometheus metrics on port 9300 at `/metrics`.
- Blueprints (in `/blueprints/`) let you declaratively define flows, stages, and policies — useful for GitOps-style config management of Authentik itself.
- Authentik version cadence: new minor releases monthly. Pin to a specific version in prod and update deliberately.
