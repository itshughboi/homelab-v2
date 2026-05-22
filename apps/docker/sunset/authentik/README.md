## UPDATE: Authentik has been replaced by Pocket ID in my stack. Much simpler and easier to use

###### Help: https://docs.goauthentik.io/docs/install-config/install/docker-compose

## Initial Setup
1. Fill out .env
2. Edit docker-compose.yaml if necessary and run
3. Create initial user
```
https://authentik.hughboi.cc/if/flow/initial-setup/
- Setup account here
Login: 
default username: akadmin
```

## Create New Admin User
1. Navigate to Directory -> Users -> Create User
username: hughboi
User Type: Internal
Email: Required
Is Active: ON
Path: users
- Then save and set a password
2. Add user to group: auhentik Admins
3. Log out and login with that new user
3. Click on gear icon in top right -> MFA Device -> Enroll
4. Deactive akadmin user


## Application Setup e.g. Portainer
1. Applications -> Providers # 1:1 ratio
- OAuth:
  - Name: portainer
  - authorization flow: implicit #can switch to explicit to prompt confirmation each time
** Copy Client ID & Client Secret
  - edirect: https://portainer.hughboi.cc
2. Go to Portainer -> Settings -> Authentication -> OAuth
- Toggle SSO: ON
- Automatic user provisioning: ON
- Custom: 
  - Enter Client ID
  - Enter Client Secret
  - Authorization URL: https://authentik.hughboi.cc/application/o/authorize/ #taken from docs.goauthentik.io 
  - Access Token URL: https://authentik.hughboi.cc/application/o/token/
  - Resource URL: https://authentik.hughboi.cc/application/o/userinfo/
  - Redirect URL: https://portainer.hughboi.cc
  - Logout URL: https://authentik.hughboi.cc/application/o/portainer/end-session/ #portainer needs to match authentik application name
  - User identifier: preferred_username
  - Scope: email openid profile
3. Back in Authentik -> Setup Application
Name: portainer
slug: portainer
Provider: portainer #provider created in step2
4. Go to Applications and you should be able to get to portainer and click on login with OAuth
5. Logout then login with internal user and grant on the new user created, make Administrator


## Proxmox Setup
1. Setup Provider
- OAuth:
  - Name proxmox
  - authorization flow: implicit
  - redirect: https://pve-srv-1.hughboi.cc:8006 
2. Go to Proxmox
- Datacenter
  - Realm
    - Add: OpenID Connect Server
    - Issuer URL: https://authentik.hughboi.cc/application/o/proxmox/
    - Realm: authentik
    - Client ID:
    -  Client Key:
    - Username Claim: username
    - Default: Checked
    - Autocreate Users: Checked 
3. Create Application
- Once that redirect works login with local user -> permissions tab -> User permission
Permissions:
- Path: /
- User hughboi@authentik
- Role: Administrator
- Propage: Checked


## Traefik Integration
help: https://docs.goauthentik.io/docs/add-secure-apps/providers/proxy/server_traefik

1. Forward Authentication is setup. Only when Authentik says they are authennticated will they get through to the application
We need to add the following to traefik

Add this to traefik/data/config.yml
```
http:
    middlewares:
        authentik:
            forwardAuth:
                address: http://authentik-server:9000/outpost.goauthentik.io/auth/traefik
                trustForwardHeader: true
                authResponseHeaders:
                    - X-authentik-username
                    - X-authentik-groups
                    - X-authentik-entitlements
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

2. New Traefik Label to attach to application:
- "traefik-http.routers.APPNAME-https.middlewares=authentik@file"

3. Go to Authentik and create new Provider
- Type: Proxy Provider
- Name: application-name
- flow: implicit (forward auth single application)
- External host: https://FQDN

4. Create Application
- Name: Application
- Slug: Application
- Provider: Provider in step 3

5. Go to Outposts -> authentik Embedded Outpost -> Edit -> Select application under **Available Applications** and then update

***
I need to play with this more especially the proxy applications. I tried to do it on redlib and it kind of worked, but not at the same time and I could still access it outside authentik

           - X-authentik-meta-outpost
           - X-authentik-meta-provider
           - X-authentik-meta-app
           - X-authentik-meta-version

```
