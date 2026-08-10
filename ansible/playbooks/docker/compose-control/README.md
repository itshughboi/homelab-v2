Stop or tear down a Docker Compose service on a remote host from Semaphore — no
manual SSH required.

## Why this exists

dock-prod services can be stopped from **Portainer** (which is connected to
dock-prod). The management-plane services on **Athena** (gitea, semaphore, bind9)
aren't in that Portainer, so stopping one otherwise means opening an SSH session.
This playbook is the no-SSH stop button for those — most useful for testing a
redeploy: stop the service here, then bring it back with `sops-deploy`.

## What it does NOT do

It doesn't start services back **up**. Bringing a service up needs its decrypted
`.env` (SOPS), which is `sops-deploy`'s job — use that. This playbook deliberately
does no SOPS decryption, because stopping/removing existing containers doesn't
need the secrets.

## ⚠️ The Gitea bootstrap exception — do NOT stop Gitea and expect Semaphore to restart it

Both this playbook and `sops-deploy` are driven by Semaphore, and **Semaphore's
first step on every run is to clone the repo from Gitea over SSH
(`ssh://git@10.10.10.8:222`)**. Gitea *is* that git-over-SSH endpoint.

So if you stop Gitea, Semaphore can no longer clone anything — every task fails at
the checkout step with `Connection refused` on port 222, including the `sops-deploy`
task that would bring Gitea back up. It's a chicken-and-egg: you can't use the tool
that depends on Gitea to start Gitea.

**Gitea is the one Athena service that must be (re)started manually**, directly on
Athena, not through Semaphore:

```sh
cd ~/homelab
./scripts/sops-run.sh gitea up -d
```

(This works because the repo is already cloned locally on Athena — no Gitea fetch
needed. It decrypts `.env.sops` in memory, no plaintext hits disk.)

Every *other* Athena service (bind9, etc.) is fine to stop/start via Semaphore —
Gitea is special only because it's Semaphore's own git source.

## Actions

| action | effect | bring back with |
|---|---|---|
| `stop` | stop containers, keep them | `sops-deploy` (or Portainer, for dock-prod) |
| `down` | stop **and remove** containers + network; **named volumes/data untouched** | `sops-deploy` |

## Usage

Always `-l`-limit the run to the single host that runs the service — the playbook
aborts if a run targets more than one host.

```sh
# stop Gitea on Athena (to test a Semaphore redeploy):
ansible-playbook -i inventory.yaml main.yaml -e service=gitea -e action=stop -l athena

# fully tear down before a clean redeploy:
ansible-playbook -i inventory.yaml main.yaml -e service=gitea -e action=down -l athena
```

**As a Semaphore Task Template:** add `service` and `action` as Survey Variables
(prompted each run), and set the template's **Limit** field to the host the
service runs on (`athena` for the management-plane services this is mostly for).
Point the template at **this playbook's own `inventory.yaml`**, not the shared
`ansible/inventories/hosts.ini` — same as sops-deploy.

## Adding a target host

Add it under `docker_hosts` in this directory's `inventory.yaml` (same as
sops-deploy). Every run must still be `-l`-limited to a single host.
