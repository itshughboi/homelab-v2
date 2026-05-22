# Sealed Secrets

Encrypts Kubernetes Secrets so they can be safely committed to Git. A controller running in-cluster holds the private key and decrypts `SealedSecret` resources back into standard Secrets at apply time.

## Why / When to Migrate

The current strategy is **imperative secrets** — secrets are created with `kubectl create secret` and never committed to Git. This works but has a gap: if the cluster is rebuilt from scratch, you need to re-create every secret manually before ArgoCD can sync.

Sealed Secrets closes that gap: encrypted secrets live in the repo, so a full cluster rebuild is just `helm install` + `argocd app sync`.

## Install

```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --set fullnameOverride=sealed-secrets-controller
```

Install the `kubeseal` CLI:
```bash
# macOS
brew install kubeseal

# Linux
KUBESEAL_VERSION=$(curl -s https://api.github.com/repos/bitnami-labs/sealed-secrets/tags | jq -r '.[0].name' | cut -c 2-)
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz
tar -xvzf kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz kubeseal
mv kubeseal /usr/local/bin/
```

## Creating a Sealed Secret

```bash
# 1. Create the plain secret as a dry-run (never applied directly)
kubectl create secret generic my-app-env -n my-app \
  --from-literal=PASSWORD=hunter2 \
  --dry-run=client \
  -o yaml > /tmp/my-app-secret.yaml

# 2. Seal it
kubeseal --format yaml < /tmp/my-app-secret.yaml > apps/kubernetes/k3s/apps/my-app/sealed-secret.yaml

# 3. Delete the plain file
rm /tmp/my-app-secret.yaml

# 4. Commit sealed-secret.yaml — it's safe to commit
```

## How Decryption Works

The controller holds an RSA private key. `SealedSecret` resources contain the secret value encrypted with the matching public key. The controller watches for `SealedSecret` objects and creates the corresponding `Secret` in the same namespace.

The encryption is namespace+name scoped — a sealed secret for `my-app/db-password` cannot be decrypted into a different namespace or with a different secret name.

## Backing Up the Controller Key

**Critical**: If the cluster is rebuilt and you lose the private key, all sealed secrets become permanently unreadable.

```bash
# Back up the key to a safe location (Vaultwarden, offline storage)
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-master.key

# To restore the key on a new cluster, apply it BEFORE installing the controller:
kubectl apply -f sealed-secrets-master.key
helm install sealed-secrets ...
```

## Migrating from Imperative Secrets

For each existing imperative secret:
1. Retrieve the current values from the running cluster:
   ```bash
   kubectl get secret my-app-env -n my-app -o jsonpath='{.data.PASSWORD}' | base64 -d
   ```
2. Re-create + seal it as above
3. Add to `apps/kubernetes/k3s/apps/my-app/sealed-secret.yaml`
4. Add to the ArgoCD `ignoreDifferences` — or remove the ignore if you now want ArgoCD to manage the secret

## Notes

- `kubeseal --fetch-cert` fetches the public key without cluster access (useful for CI)
- Sealed secrets can be re-encrypted without decryption using `kubeseal --re-encrypt`
- The controller rotates its own key annually by default — old keys are kept for decryption of existing secrets
