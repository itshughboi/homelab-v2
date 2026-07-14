Documentation: https://docs.gitea.com/

## Routing (Athena, not dock-prod)

Gitea runs on Athena, but Traefik runs on dock-prod — Traefik's Docker-label discovery only
sees containers on its own host, so `compose.yaml` publishes port 3000 directly and the
`gitea.hughboi.cc` route lives as a static entry in
[`apps/docker/traefik/data/config.yml`](../traefik/data/config.yml) on dock-prod instead of
labels here. See [6-docker/index.md](../../../docs/6-docker/index.md) for the full explanation.
If `gitea.hughboi.cc` ever 404s/times out after this container is confirmed healthy, that
static route (or Traefik's reachability to `10.10.10.8:3000` across the VLAN firewall) is
the first place to check — not this compose file.

## SSH Keys
1. On gitea... -> Profile -> SSH -? Add Key -> upload public key
2. On client, e.g. MacOS, test ssh using port 222. 
```
ssh -T -p 222 git@gitea.hughboi.cc
```
3. If that works, we need to edit the ssh config file so we don't need to keep specifying port
Ctrl + Shift + P -> Remote-SSH: Open SSH Configuration File and add the following: <br>
```
Host gitea.hughboi.cc
  HostName gitea.hughboi.cc
  User git
  Port 222
  IdentityFile ~/.ssh/id_ed25519 # optional
  IdentitiesOnly yes # optional
```
- This also adds this to the ~/.ssh/config file on your client (dock-prod e.g.)


## OIDC



## Runner
1. Grab registration token from **Settings** -> **Actions** -> **Runners** -> **Create New Runner** and paste it into env
2. If I need to recreate config file back to defaults run this:
```sh
sudo docker run --entrypoint="" --rm docker.io/gitea/act_runner:0.4.0 act_runner generate-config > config.yml
```
3. Stand up container and you will see it in active runners once connected

## Actions
1. Clone desired repo to my machine
2. Add a '.gitea' folder
3. add a 'workflows' folder under '.gitea.'
4. Give file a name like 'test.yaml'
5. Commit/push back to repo and it should start going
```
mkdir -p .gitea/workflows
```
```
code gitea/workflows/test.yaml
```
```
git add .gitea/workflows/test.yaml
git commit -m "Add test Gitea Actions workflow"
git push origin main
```

