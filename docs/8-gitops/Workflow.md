# GitOps Change Workflow

How to make a change to this repo **safely** — from "I want to edit something" to "it's running on
the cluster." Pairs with [index.md](index.md) (the ArgoCD machinery) and the
[k3s GitOps section](../7-k3s/index.md#gitops-argocd).

> [!NOTE] Read this first if you're about to "just commit to main"
> On a GitOps repo, `main` is not "latest code" — it's **the live cluster state**. The habit below
> is what stops a typo from becoming a deploy.

---

## The mental model

```
feature branch ──(PR + CI + review)──▶ main ──(ArgoCD auto-syncs)──▶ cluster
   "draft"              "promote"         "live"        "deployed"
ArgoCD ignores it                    ArgoCD watches this (targetRevision: main)
```

- **branch = draft.** ArgoCD only watches `main`, so commits on a branch deploy **nothing**. A
  branch is a safe place to experiment.
- **main = live.** `root-app.yaml` + `apps-appset.yaml` use `targetRevision: main` with auto-sync
  (`prune` + `selfHeal`). A change landing on `main` **is** a deploy.
- **merge = the deploy button.** That's why you review the PR — you're approving *"this goes live,"*
  not just *"this code."*

---

## The flow (with commands)

Example: pin AdGuard's image.

```sh
# 1. Branch off main (ArgoCD ignores this branch)
git switch -c fix/pin-adguard

# 2. Make the change + commit
#    edit apps/kubernetes/k3s/networking/adguard/adguard-deployment.yml
git add -A && git commit -m "fix(adguard): pin image to v0.107.x"

# 3. Push the branch — CI runs automatically (see "Validation" below)
git push -u origin fix/pin-adguard

# 4. Open a PR (branch -> main), review the diff, wait for CI green
gh pr create --base main --fill        # or open it in the GitHub/Gitea UI

# 5. Merge the PR -> the commit is now on main
#    -> ArgoCD (polling ~3 min, or via webhook) applies it to the cluster
```

---

## Two kinds of "testing" — know which you need

| | Catches | Where it happens | Needs a running cluster? |
| --- | --- | --- | --- |
| **Validation** | Bad YAML, typos, wrong fields, invalid k8s schema | **CI on the branch/PR** (`kubeconform` + `kubectl --dry-run`, yamllint, gitleaks, Trivy) | **No** |
| **Runtime** | "Does the app actually start and behave right?" | A running cluster (real or throwaway) | **Yes** |

The "a syntax error that ArgoCD tries to deploy" worry is **Validation** — caught by CI *before*
merge, with no cluster involved. That's the whole reason to branch: it gets your change in front of
CI before it can reach `main`.

> [!IMPORTANT] CI only runs *off* `main`
> `.gitea/workflows/ci.yaml` triggers on **push to any branch except `main`** and on **PRs to
> `main`**. So committing **directly** to `main` **skips every check** (yamllint, kubeconform,
> gitleaks, Trivy). The branch + PR is the *only* path that validates your change.

---

## Three safety layers

```
1. CI on the branch   -> blocks invalid manifests before merge          (most bugs)
2. ArgoCD health      -> shows the moment a pod won't start after deploy
3. git revert         -> one command, ArgoCD rolls the cluster back      (escape hatch)
```

**Rollback.** CI guarantees a manifest is *valid*; it can't know your new memory limit is too low
and the app will OOM. For "valid but wrong," revert the commit:

```sh
git revert <bad-commit-sha>     # creates an inverse commit
git push                        # via a branch+PR (or direct on main, pre-ArgoCD)
# ArgoCD sees main changed -> restores the previous working state
```

---

## Risky changes → test on a throwaway cluster first

For a change scary enough that you want to *watch it run* before it touches the real cluster (a big
Longhorn bump, restructuring an app's storage), spin up a local cluster, apply just that change,
observe, throw it away:

```sh
k3d cluster create scratch      # free, runs on your laptop, ~30s
# kubectl apply / argocd app sync your branch against it, watch it, then:
k3d cluster delete scratch
```

Same muscle as the bare-metal rebuild drill — you won't need it most weeks.

---

## Right now: pre-ArgoCD

ArgoCD **isn't running yet** (the cluster is still being built). Until it is, steps 1–5 work the
same but **nothing auto-deploys** — there's no "live" to break. So pre-launch it's fine to commit
straight to `main` and move fast.

**The day you bootstrap ArgoCD, switch the habit back on:** `main` becomes the deploy trigger, and
`branch → PR → merge` becomes load-bearing. Consider adding **branch protection** on `main`
(GitHub/Gitea) that requires CI to pass before merge — then the gate is enforced, not just
remembered.

---

## Quick reference

```sh
git switch -c <type>/<short-desc>      # feat/  fix/  chore/  docs/
# …edit…
git add -A && git commit -m "type(scope): summary"
git push -u origin <branch>            # CI runs here
# open PR → review → CI green → merge to main → ArgoCD deploys
git revert <sha>                       # undo a bad change; ArgoCD rolls back
```
