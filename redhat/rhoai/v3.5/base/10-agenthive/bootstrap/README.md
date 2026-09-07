# GitOps Bootstrap — One-Time Cluster Setup

Apply this Kustomize base ONCE to prepare the cluster for ArgoCD management.

## Prerequisites

- OpenShift 4.18+ cluster with admin access
- `oc` CLI logged in as cluster-admin
- `kubeseal` CLI version **0.27.3** installed locally ([install](https://github.com/bitnami-labs/sealed-secrets/releases/tag/v0.27.3)). The CLI version must match the controller version in `sealed-secrets.yaml`; a mismatch produces ciphertext the controller cannot decrypt.

## Bootstrap (One Command)

```bash
oc apply -k platform/gitops/bootstrap/
```

This installs:
- OpenShift GitOps operator (ArgoCD)
- Sealed Secrets controller + CRD
- Agent Sandbox CRD (Red Hat build via Subscription)
- DataScienceCluster patch (enables OGX, MLflow, TrustyAI, Pipelines)
- OdhDashboardConfig patch (enables Gen AI Studio, AutoRAG)

Wait ~2 minutes for operators to reconcile.

## SealedSecret Health Check (Recommended)

Argo CD's built-in health check for SealedSecrets races with the controller's
status updates, causing false `Degraded` reports. Add a custom health check
to the ArgoCD CR so SealedSecrets always report Healthy (the controller still
decrypts them; only the status condition is unreliable):

```bash
oc patch argocd openshift-gitops -n openshift-gitops --type merge -p '{
  "spec": {
    "extraConfig": {
      "resource.customizations.health.bitnami.com_SealedSecret": "hs = {}\nhs.status = \"Healthy\"\nhs.message = \"Controller does not report resource status\"\nreturn hs\n"
    }
  }
}'
```

This is the [Argo CD FAQ](https://argo-cd.readthedocs.io/en/stable/faq/#why-are-resources-of-type-sealedsecret-stuck-in-the-progressing-state) recommendation. The `extraConfig` field persists through operator reconciliation.

## Seal Secrets (Required Before App-of-Apps)

After the Sealed Secrets controller is running, you must seal all secrets
for your cluster. Each cluster has a unique encryption key.

### Step 1: Fetch the cluster's public cert

```bash
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=sealed-secrets \
  > platform/gitops/secrets/pub-cert.pem
```

The public cert is safe to commit — it can only encrypt, not decrypt.

### Step 2: Seal each secret

Use the helper script (runs locally, never on cluster):

```bash
platform/gitops/secrets/seal-secrets.sh
```

Or seal manually:

```bash
# Example: MinIO credentials
oc create secret generic minio-credentials -n minio \
  --from-literal=root-user=minioadmin \
  --from-literal=root-password=<YOUR_PASSWORD> \
  --dry-run=client -o yaml | \
  kubeseal \
    --cert platform/gitops/secrets/pub-cert.pem \
    --format yaml \
    --scope strict \
    > platform/gitops/secrets/minio-credentials.yaml
```

Repeat for ALL secrets listed in `platform/gitops/secrets/kustomization.yaml`.

### Step 3: Commit sealed secrets

```bash
git add platform/gitops/secrets/
git commit -m "chore: seal secrets for cluster $(oc whoami --show-server | cut -d/ -f3)"
git push
```

### Step 3.5: Register Argo CD repo credentials (private repo only)

If this repo is private, Argo CD needs HTTPS credentials to clone it.
Use the same GitHub PAT you provided to `seal-secrets.sh`:

```bash
oc create secret generic repo-ai-platforms -n openshift-gitops \
  --from-literal=type=git \
  --from-literal=url=https://github.com/rrbanda/ai-platforms.git \
  --from-literal=username=x-access-token \
  --from-literal=password="<YOUR_GITHUB_PAT>" \
  --dry-run=client -o yaml | \
  oc label -f - --local argocd.argoproj.io/secret-type=repository -o yaml | \
  oc apply -f -
```

Without this, every Application will fail with `authentication required`.

### Step 4: Deploy App-of-Apps

```bash
oc apply -f platform/gitops/apps/app-of-apps.yaml
```

ArgoCD now manages everything from git with self-healing.

## GitHub Webhook (Recommended)

By default ArgoCD polls Git every 3 minutes. Configure a webhook for
near-instant sync after CI pushes a manifest change.

```bash
# 1. Generate a random secret
WEBHOOK_SECRET=$(openssl rand -hex 20)

# 2. Store it in the ArgoCD secret
oc patch secret argocd-secret -n openshift-gitops \
  --type merge -p "{\"stringData\":{\"webhook.github.secret\":\"$WEBHOOK_SECRET\"}}"

# 3. In GitHub → Settings → Webhooks → Add webhook:
#    Payload URL: https://<argocd-route>/api/webhook
#    Content type: application/json
#    Secret: <the value from step 1>
#    Events: Just the push event
```

See [ArgoCD webhook docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/webhook/).

> **Note:** The CD pipeline commits via `GITHUB_TOKEN`, which does not
> fire GitHub push events (a built-in infinite-loop safeguard). ArgoCD
> will pick up CD commits via polling. If you need instant sync for CD
> commits, use a GitHub App token instead of `GITHUB_TOKEN` in the
> workflow.

## Sync Wave Order

ArgoCD deploys resources in this order:

| Wave | Resources | Why |
|------|-----------|-----|
| -5 | SealedSecrets | Must decrypt before anything references them |
| 0 | OpenShell (Helm), RBAC | Infrastructure foundations |
| 1 | MinIO, Milvus, etcd | Data stores (namespaces auto-created via `CreateNamespace=true`) |
| 2 | OGX Server, NetworkPolicies | Depends on Milvus |
| 3 | DSPA, OpenShift MCP | Pipelines; shared cluster MCP |
| 4 | Agent Sandboxes, RHOAI MCP | Depends on OpenShell, secrets, MCP |
| 5 | Eval RBAC + ConfigMaps | After agent namespace stable |

## Key Backup (Critical)

Back up the Sealed Secrets controller's private key. Without it, you cannot
decrypt existing sealed secrets if the controller is reinstalled.

```bash
oc get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-master-key-backup.yaml
```

Store this file securely OUTSIDE of git (e.g., password manager, vault).

## Re-sealing (After Key Rotation)

The controller rotates keys every 30 days by default. Old secrets still decrypt
(old keys are retained). To re-seal with the latest key:

```bash
kubeseal --fetch-cert --controller-name=sealed-secrets-controller \
  --controller-namespace=sealed-secrets > platform/gitops/secrets/pub-cert.pem
# Then re-run seal-secrets.sh
```
