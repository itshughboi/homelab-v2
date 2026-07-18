# Docker Host Setup

Installing Docker + the portable path env vars used by the compose files. Service catalog and
startup order: [index.md](index.md).

### Docker Installation
1. Set up Docker's apt repository
```sh
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
```
2. Install the Docker packages
```sh
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```
3. Verify successful install
```sh
sudo systemctl status docker
```


### Global File Path Remedy (legacy — mostly unused)
- Originally intended to avoid hardcoding paths across compose files by referencing
  `${CODE_ROOT}`/`${DATA_ROOT}` env vars, settable in one place. In practice, this convention
  never got broad adoption — a full-repo audit (2026-07) found only `apps/docker/wazuh/`
  (itself never actually deployed) still uses it. Every other service hardcodes its real,
  verified-against-production path directly in `compose.yaml` instead (e.g.
  `/home/hughboi/data/<service>/...`, or `./config` relative to the compose file's own
  directory in this repo checkout). Don't add new `${CODE_ROOT}`/`${DATA_ROOT}` references to
  new services — match the hardcoded-real-path convention everything else already uses.

If wazuh (or anything else still on this convention) is ever revived, the original setup was:
1. Add to `~/.bashrc`
```sh
export CODE_ROOT="/home/hughboi/homelab/docker/code"
export DATA_ROOT="/home/hughboi/data"
```
2. Apply
```sh
source ~/.bashrc
```
3. Reference `${CODE_ROOT}` or `${DATA_ROOT}` in `.env` or `compose.yaml`

**Ansible + Gitea Runner**
- Often run in non-interactive shells that DO NOT load `.bashrc`.
- Fix: set the same two vars in that service's own `.env` file instead, since Compose reads
  `.env` regardless of shell.