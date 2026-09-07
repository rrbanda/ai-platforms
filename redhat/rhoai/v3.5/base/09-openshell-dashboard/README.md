# OpenShell Dashboard -- GitOps Deployment on OpenShift

Deploys the [OpenShell Dashboard](https://github.com/Gkrumbach07/openshell-dashboard) to OpenShift via ArgoCD. The dashboard is a standalone web admin UI for the OpenShell gateway -- it connects to an **existing** OpenShell installation (deployed via `09-openshell/`).

## Architecture

```
                         ┌─── OpenShift Route (edge TLS) ───┐
                         │                                   │
  Browser ──HTTPS──►  Route  ──►  oauth2-proxy (:4180)      │
                                      │                      │
                                  upstream                   │
                                      │                      │
                                  BFF (:8080) ◄──────────────┘
                                      │
                                  gRPC + Bearer
                                      │
                              OpenShell Gateway
                           (openshell namespace)
```

The deployment follows [ADR 0002 (relay-only auth)](https://github.com/Gkrumbach07/openshell-dashboard/blob/main/docs/adrs/0002-auth-relay-only-bff.md): the BFF never validates tokens. An oauth2-proxy sidecar terminates OIDC against the cluster's Dex instance and injects `x-forwarded-access-token` on every request.

## Prerequisites

- OpenShell gateway deployed in the `openshell` namespace (`09-openshell/`)
- Dex (or another OIDC IdP) deployed in the `openshell` namespace (`08-keycloak/`)
- An `openshell-dashboard` OIDC client registered in Dex (see Dex config in `deploy/openshift/dex/`)

## Files

| File | Purpose |
|------|---------|
| `namespace.yaml` | `openshell-dashboard` namespace |
| `serviceaccount.yaml` | Pod identity |
| `configmap.yaml` | BFF configuration (gateway URL, feature flags, auth settings) |
| `oauth2-proxy-config.yaml` | oauth2-proxy OIDC configuration (patched per-cluster) |
| `deployment.yaml` | Pod: oauth2-proxy sidecar + BFF container |
| `service.yaml` | ClusterIP service on port 4180 (proxy) |
| `route.yaml` | Edge-terminated OpenShift Route |
| `networkpolicy.yaml` | Restrict ingress to router, egress to gateway + IdP |
| `secret-template.yaml` | Template for oauth2-proxy secrets (do not apply directly) |
| `kustomization.yaml` | Kustomize entry point |
| `overlays/example/` | Per-cluster overlay template |

## Deployment

### 1. The ArgoCD Application is already registered

`applications/09c-openshell-dashboard.yaml` is picked up by the app-of-apps at sync wave 3 (after the OpenShell gateway at wave 3).

### 2. Seal secrets for your cluster

```bash
# Generate a cookie secret
export COOKIE_SECRET=$(python3 -c "import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())")

# Your Dex client secret for the openshell-dashboard client
export OAUTH2_CLIENT_SECRET="<from-dex-config>"

# Seal the secret
oc -n openshell-dashboard create secret generic openshell-dashboard-oauth2 \
  --from-literal=OAUTH2_PROXY_CLIENT_SECRET="$OAUTH2_CLIENT_SECRET" \
  --from-literal=OAUTH2_PROXY_COOKIE_SECRET="$COOKIE_SECRET" \
  --dry-run=client -o yaml | kubeseal -o yaml \
  > redhat/rhoai/v3.5/overlays/<cluster>/openshell-dashboard-oauth2-sealed.yaml
```

### 3. Create a cluster overlay

```bash
cp -r overlays/example overlays/<your-cluster>

# Edit overlays/<your-cluster>/kustomization.yaml:
#   - Replace REPLACE_CLUSTER_DOMAIN with your cluster's apps domain
#   - Uncomment the sealed secret resource
#   - Optionally pin the image tag

git add overlays/<your-cluster>
git commit -m "feat: add openshell-dashboard overlay for <your-cluster>"
git push
```

### 4. Switch ArgoCD to use the overlay (optional)

If using per-cluster overlays, patch the ArgoCD Application source path:

```yaml
# In the Application or via an overlay patch:
spec:
  source:
    path: redhat/rhoai/v3.5/base/09-openshell-dashboard/overlays/<your-cluster>
```

## Configuration

### Gateway URL

The `OPENSHELL_GATEWAY_URL` in `configmap.yaml` defaults to the in-cluster service DNS:

```
grpc://openshell-gateway.openshell.svc.cluster.local:50051
```

If the gateway uses TLS within the cluster, change to `grpcs://` and mount the CA cert.

### Feature Flags

All features are enabled by default. Disable per deployment by patching the ConfigMap:

```yaml
# Example: disable terminal (WebSocket not supported through federation proxy)
FEATURE_TERMINAL: "false"
```

### Image

The base uses `quay.io/gkrumbach07/openshell-dashboard:latest`. Pin to a specific SHA in your overlay:

```yaml
images:
  - name: quay.io/gkrumbach07/openshell-dashboard
    newTag: sha-abc1234
```
