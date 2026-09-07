---
name: rhoai-disconnected-deploy
description: "Battle-tested procedure for deploying Red Hat OpenShift AI on a disconnected (air-gapped) OpenShift cluster — covers storage sizing, digest-pinned mirroring, workbench image gaps, dual-layer CA trust, DSC v2 API, and OCP 4.22+ Istio changes."
version: 3.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Disconnected, Air-gapped, oc-mirror, Mirror, DSC v2, DSCI, Deployment]
---

# RHOAI Disconnected Deployment (v3)

Deploy Red Hat OpenShift AI on a disconnected (air-gapped) OpenShift cluster. This procedure is derived from the [disconnected-rhoai](https://github.com/rh-aiservices-bu/disconnected-rhoai) reference repo, verified end-to-end on OCP 4.20 / RHOAI 3.4.2 and OCP 4.22 / RHOAI 3.4.3.

## Trigger Conditions

- "Deploy RHOAI in a disconnected environment"
- "How do I set up OpenShift AI in an air-gapped cluster?"
- "Generate the mirror configuration for RHOAI"
- "What images do I need to mirror for OpenShift AI?"
- "Install RHOAI operators offline"
- "Set up RHOAI without internet access"

---

## Assumptions

- OpenShift 4.19+ is already installed and running
- You have cluster-admin access
- A connected host (low side / jump box) has internet access
- A disconnected host (high side / bastion) can reach the cluster but not the internet
- Content crosses the air gap via rsync/sneakernet

---

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| mcp_rhoai | cluster_summary | Check RHOAI installation status and DSC state |
| mcp_rhoai | explore_cluster | Inspect platform health, workbenches, model serving |
| mcp_openshift | resources_list | List Namespace, CatalogSource, IDMS, ITMS, Subscription, CSV, MCP |
| mcp_argocd | list_applications | Check ArgoCD app state (GitOps path) |

---

## Storage Sizing (Critical)

The RHOAI mirror is **~517 GB** (171 operator images + 63 workbench images). Three copies exist simultaneously during the push phase.

| Host | Holds | Measured | Volume Required |
|------|-------|---------|----------------|
| Low side (connected) | Archive + oc-mirror cache | ~1,055 GB | **1,500 GB** |
| High side (disconnected) | Archive + cache + Quay storage | ~1,650 GB | **2,000 GB** |

Tell the user these numbers **before** they begin. Running out of disk during the push phase can render the bastion unreachable (see Troubleshooting).

---

## Template Files (Use Instead of Generating YAML)

This repo includes battle-tested manifest templates that the agent should point users to instead of generating YAML from scratch. This saves tokens and ensures accuracy.

| Template | Path | Purpose |
|----------|------|---------|
| ImageSetConfiguration | `manifests/disconnected/mirror/imageset-config-rhoai.yaml` | Mirror config with placeholder digests and additionalImages instructions |
| Disable default catalogs | `manifests/disconnected/cluster-config/disable-default-catalogs.yaml` | OperatorHub patch |
| Registry CA trust | `manifests/disconnected/cluster-config/registry-ca-trust.yaml` | Layer 1 CA trust (node/CRI-O) |
| CatalogSource alias | `manifests/disconnected/cluster-config/catalog-source-alias.yaml` | `redhat-operators` alias for ingress operator |
| Pull secret patch | `manifests/disconnected/cluster-config/pull-secret-patch.sh` | Script to add mirror creds |
| cert-manager operator | `manifests/disconnected/operators/cert-manager.yaml` | NS + OG + Subscription |
| Service Mesh 3 | `manifests/disconnected/operators/servicemesh3.yaml` | OCP 4.19-4.21 only |
| NFD operator | `manifests/disconnected/operators/nfd.yaml` | NS + OG + Subscription |
| GPU operator | `manifests/disconnected/operators/gpu-operator.yaml` | NS + OG + Subscription (certified catalog) |
| RHOAI operator | `manifests/disconnected/operators/rhoai.yaml` | NS + OG (AllNamespaces) + Subscription |
| DSCInitialization | `manifests/disconnected/rhoai/dsci.yaml` | Layer 2 CA trust (pod-level, customCABundle) |
| DataScienceCluster v2 | `manifests/disconnected/rhoai/dsc-v2.yaml` | All 14 components explicit |
| ArgoCD Applications | `manifests/disconnected/argocd/` | GitOps wrappers with sync-waves |
| ArgoCD app-of-apps | `manifests/disconnected/argocd/app-of-apps.yaml` | Root Application (the ONLY one to apply directly) |
| ArgoCD health checks | `manifests/disconnected/argocd/argocd-health-checks.yaml` | REQUIRED: teaches ArgoCD when Subscriptions/DSCI/DSC are healthy |

**For GitOps path:** The ArgoCD health checks MUST be applied first. Without them, ArgoCD considers a Subscription "healthy" the moment it exists (not when the CSV reaches Succeeded), so it immediately advances to the next sync-wave before operators are installed. Then apply only the `app-of-apps.yaml` — it manages the 3 child Applications.

**For each step below, tell the user: "Copy `<template file>` and replace `<PLACEHOLDER>` with your value" instead of generating the YAML inline.**

Reference examples from verified deployments are in `examples/disconnected/rhoai-3.4.2-ocp-4.20.30/` for comparison.

---

## Procedure

### Step 1: Install Mirror Registry

**Where:** Download on low side (connected), transfer to high side, install on high side.

First, download the mirror-registry installer on the connected host:

```bash
# On the LOW SIDE (connected):
curl -L -o mirror-registry-amd64.tar.gz \
  https://developers.redhat.com/content-gateway/rest/mirror/pub/openshift-v4/clients/mirror-registry/latest/mirror-registry-amd64.tar.gz
```

Transfer it to the high side (along with oc and oc-mirror tools). Then install:

```bash
# On the HIGH SIDE (disconnected):
tar -xzf mirror-registry-amd64.tar.gz -C ~/
./mirror-registry install \
  --quayHostname $(hostname -f) \
  --quayRoot /home/$USER/quay-install \
  --quayStorage /mnt/mirror/quay-storage
```

**Critical:** `--quayStorage` MUST point to the large volume, not `$HOME`. Without it, Quay uses a rootless podman volume on the root filesystem. A 500 GB push fills a 299 GB root disk, and at zero bytes free `dhclient` cannot write a lease — the host reboots with no network.

**Critical:** `--quayHostname` must be a FQDN that resolves from the cluster nodes, not just from the bastion.

Trust the CA on the bastion:

```bash
sudo cp /home/$USER/quay-install/quay-rootCA/rootCA.pem \
        /etc/pki/ca-trust/source/anchors/quay-rootCA.pem
sudo update-ca-trust extract
```

Record these values — they are needed throughout:
- `MIRROR_REGISTRY` = `$(hostname -f):8443`
- `MIRROR_REGISTRY_PASSWORD` = (output from mirror-registry install)
- `MIRROR_REGISTRY_CA_FILE` = `/home/$USER/quay-install/quay-rootCA/rootCA.pem`

---

### Step 2: Configure Authentication

**Where:** Low side (for mirroring), High side (for pushing).

Seed the container auth file with the Red Hat pull secret:

```bash
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
mkdir -p $XDG_RUNTIME_DIR/containers
cp ~/pull-secret.json $XDG_RUNTIME_DIR/containers/auth.json
```

On the high side, also log into the mirror registry:

```bash
podman login --authfile $XDG_RUNTIME_DIR/containers/auth.json \
  -u init -p "$MIRROR_REGISTRY_PASSWORD" "$MIRROR_REGISTRY"
```

---

### Step 2b: Fetch Tools

**Where:** Low side (connected host). `oc` and `oc-mirror` must match the target OpenShift release.

```bash
V=<OCP_RELEASE_VERSION>   # e.g. 4.20.30
curl -L -o oc.tar.gz        "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${V}/openshift-client-linux.tar.gz"
curl -L -o oc-mirror.tar.gz "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${V}/oc-mirror.tar.gz"

mkdir -p ~/bin && tar -xzf oc.tar.gz -C ~/bin oc kubectl && tar -xzf oc-mirror.tar.gz -C ~/bin
chmod +x ~/bin/oc ~/bin/kubectl ~/bin/oc-mirror
export PATH="$HOME/bin:$PATH"
```

Copy the tools to the staging area so they cross the gap with the mirror archives:

```bash
mkdir -p /mnt/mirror/tools
cp ~/bin/oc ~/bin/kubectl ~/bin/oc-mirror /mnt/mirror/tools/
```

---

### Step 3: Generate ImageSetConfiguration

**Where:** Low side (connected host).

#### 3.1 Digest-pin the catalog images BEFORE mirroring

**Critical:** The configuration must match what was recorded when the archive was built. Editing it afterwards — even just swapping a tag for its digest — makes `oc-mirror` fall back to the network during the push, which fails 403 on the disconnected host. **Never edit the ImageSetConfiguration after mirroring.**

Resolve the catalog digest:

```bash
OCP_VERSION=4.20
skopeo inspect --raw docker://registry.redhat.io/redhat/redhat-operator-index:v${OCP_VERSION} \
  | jq -r '.manifests[] | select(.platform.architecture=="amd64") | .digest'
```

Repeat for `certified-operator-index` if mirroring the GPU operator.

#### 3.2 `defaultChannel` is REQUIRED

**Critical:** Every filtered package MUST include `defaultChannel`. Without it, oc-mirror emits `"invalid default channel configuration"` and refuses to generate the catalog.

#### 3.3 ImageSetConfiguration (from verified deployment)

```yaml
apiVersion: mirror.openshift.io/v2alpha1
kind: ImageSetConfiguration
mirror:
  operators:
    - catalog: registry.redhat.io/redhat/redhat-operator-index@sha256:<PINNED_DIGEST>
      packages:
        - name: rhods-operator
          defaultChannel: stable-3.4
          channels:
            - name: stable-3.4
              minVersion: "3.4.2"
              maxVersion: "3.4.2"
        - name: openshift-cert-manager-operator
          defaultChannel: stable-v1
          channels:
            - name: stable-v1
        - name: servicemeshoperator3
          defaultChannel: stable
          channels:
            - name: stable
        - name: nfd
          defaultChannel: stable
          channels:
            - name: stable
    - catalog: registry.redhat.io/redhat/certified-operator-index@sha256:<PINNED_DIGEST>
      packages:
        - name: gpu-operator-certified
          defaultChannel: stable
          channels:
            - name: stable
  additionalImages:
    # 63 workbench images — see Step 3.4
```

#### 3.4 The 63 images oc-mirror CANNOT find

**Why:** Workbench and notebook images are referenced through runtime ImageStreams created by the RHOAI operator, NOT from the operator bundle's `relatedImages`. oc-mirror only processes `relatedImages`. Without these images, RHOAI installs and the dashboard loads, but creating a workbench fails with `ImagePullBackOff`.

Fetch the version-matched list:

```bash
curl -sfL https://raw.githubusercontent.com/red-hat-data-services/rhoai-disconnected-install-helper/main/rhoai-<VERSION>.md \
  | awk '/^# Additional images/{a=1; next} /^# (Unsupported|ImageSetConfiguration)/{a=0} a' \
  | grep -oE '(quay\.io|registry\.redhat\.io)[^ ]+@sha256:[a-f0-9]+' | sort -u
```

The helper repo tries `rhoai-<x.y.z>.md` then falls back to `rhoai-<x.y>.md`. Add every returned image to the `additionalImages` section. Budget an extra 100–200 GB for these images.

---

### Step 4: Mirror to Disk

**Where:** Low side (connected host).

```bash
oc-mirror --v2 \
  --config imageset-config.yaml \
  --cache-dir /mnt/mirror/oc-mirror-cache \
  --image-timeout 60m \
  --parallel-images 2 \
  --retry-times 6 \
  file:///mnt/mirror/criab-mirror
```

**Critical — `--image-timeout 60m` is NOT optional.** RHOAI includes a 9 GB single-layer InstructLab image. At the default 10m timeout, oc-mirror skips the entire operator bundle — reporting "148/150 copied" and producing no archive at all. Never judge a mirror by the image count; check for the `.tar`.

**Critical — `--cache-dir` is NOT optional.** The default is `$HOME/.oc-mirror` on the root filesystem. The cache reaches ~520 GB.

**For NVIDIA images:** Add `--remove-signatures` to the mirror-to-disk command ONLY. The NVIDIA partner registry on `registry.connect.redhat.com` has no published sigstore signature, and one failing image fails the entire run. **Never pass `--remove-signatures` on the push step** — it blocks manifest rewriting and takes the entire rhods-operator bundle down.

This takes **~8 hours** for the RHOAI batch. Monitor progress by watching the archive file size:

```bash
ls -l /mnt/mirror/criab-mirror/*.tar; sleep 30; ls -l /mnt/mirror/criab-mirror/*.tar
```

---

### Step 5: Transfer Across the Air Gap

**Where:** Low side → High side.

```bash
rsync -a --partial --info=progress2 \
  -e "ssh -o StrictHostKeyChecking=no" \
  /mnt/mirror/criab-mirror/mirror_*.tar \
  /mnt/mirror/criab-mirror/imageset-config.yaml \
  /mnt/mirror/criab-mirror/tools/ \
  ${USER}@${HIGH_IP}:/mnt/mirror/criab-mirror/
```

Verify sizes match on both sides. For a 500 GB payload, checksums cost hours and rsync already verifies every block in transit.

---

### Step 6: Push to Mirror Registry

**Where:** High side (disconnected host).

```bash
oc-mirror --v2 \
  --config /mnt/mirror/criab-mirror/imageset-config.yaml \
  --cache-dir /mnt/mirror/oc-mirror-cache \
  --image-timeout 60m \
  --parallel-images 2 \
  --retry-times 6 \
  --from file:///mnt/mirror/criab-mirror \
  docker://${MIRROR_REGISTRY}/rhoai
```

**Do NOT pass `--remove-signatures` on the push.** It belongs only on the mirror-to-disk phase.

This emits cluster resources under `working-dir/cluster-resources/`:

| File | Kind | Purpose |
|------|------|---------|
| `idms-oc-mirror.yaml` | ImageDigestMirrorSet | Digest pull redirection |
| `itms-oc-mirror.yaml` | ImageTagMirrorSet | Tag pull redirection |
| `cs-*.yaml` | CatalogSource | The mirrored catalogs |

**Never hand-write these** — they must match what was actually mirrored.

---

### Step 7: Configure the Cluster for the Mirror

**Where:** High side, logged into the cluster.

#### 7a. Add mirror registry credentials to global pull secret

```bash
oc get secret/pull-secret -n openshift-config \
  --template='{{index .data ".dockerconfigjson" | base64decode}}' > /tmp/ps.json
oc registry login --registry="$MIRROR_REGISTRY" \
  --auth-basic="init:$MIRROR_REGISTRY_PASSWORD" --to=/tmp/ps.json
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=/tmp/ps.json
```

#### 7b. Trust the registry CA cluster-wide (node-level)

This is **layer 1** of registry CA trust — it enables CRI-O on each node to pull images from the mirror.

```bash
oc create configmap registry-cas -n openshift-config \
  --from-file="${MIRROR_REGISTRY_FQDN}..8443=${MIRROR_REGISTRY_CA_FILE}" \
  --dry-run=client -o yaml | oc apply -f -
oc patch image.config.openshift.io/cluster --type=merge \
  -p '{"spec":{"additionalTrustedCA":{"name":"registry-cas"}}}'
```

The `..8443` in the key is not a typo — a literal `..` encodes the port separator in OpenShift's trusted CA config.

**Layer 2** (pod-level trust for workbenches and pipelines) is handled later in Step 10 via `DSCInitialization.spec.trustedCABundle`. Pods do NOT mount the node trust store. Both layers are required.

#### 7c. Apply IDMS and ITMS (this reboots every node)

```bash
oc apply -f working-dir/cluster-resources/idms-oc-mirror.yaml
oc apply -f working-dir/cluster-resources/itms-oc-mirror.yaml
oc get mcp -w   # Wait for UPDATED=True, UPDATING=False on all pools
```

**NOT ICSP.** oc-mirror v2 generates ImageDigestMirrorSet and ImageTagMirrorSet. ICSP is deprecated.

#### 7d. Disable default OperatorHub catalogs

```bash
oc patch OperatorHub cluster --type=merge \
  -p '{"spec":{"disableAllDefaultSources":true}}'
```

#### 7e. Apply mirrored CatalogSources

```bash
oc apply -f working-dir/cluster-resources/cs-*.yaml
```

#### 7f. Create `redhat-operators` CatalogSource alias

**Why:** The ingress operator auto-creates a Subscription for `servicemeshoperator3` against the name `redhat-operators` and reconciles it. Without this alias, OSSM 3 never installs and KServe / Data Science Gateway cannot function.

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: redhat-operators
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: <MIRROR_REGISTRY>/rhoai/redhat/redhat-operator-index:v<OCP_VERSION>
  displayName: Red Hat Operators (mirrored)
  publisher: Red Hat
```

Verify all CatalogSources are READY:

```bash
oc get catalogsource -n openshift-marketplace
```

The generated CatalogSource name from oc-mirror will be something like `cs-redhat-operator-index-sha256-8d67e`. Find the exact name:

```bash
oc get catalogsource -n openshift-marketplace -o name
```

All Subscriptions in later steps must reference this exact generated name as their `source`.

---

### Step 8: Install Dependency Operators

**Where:** High side. **Order matters.**

Each operator follows the pattern: Namespace → OperatorGroup → Subscription. The CatalogSource `source` name is generated by oc-mirror. Use the name discovered in Step 7f.

#### Installation order

| # | Package | Namespace | Channel | Catalog | Why First |
|---|---------|-----------|---------|---------|-----------|
| 1 | `openshift-cert-manager-operator` | `cert-manager-operator` | `stable-v1` | redhat-operator-index | RHOAI 3.x will not reconcile without it |
| 2 | `servicemeshoperator3` | `openshift-operators` | `stable` | redhat-operator-index | Data Science Gateway (OCP 4.19-4.21 only) |
| 3 | `nfd` | `openshift-nfd` | `stable` | redhat-operator-index | Labels GPU nodes for NVIDIA operator |
| 4 | `gpu-operator-certified` | `nvidia-gpu-operator` | `stable` | certified-operator-index | GPU drivers (optional, harmless without GPU nodes) |

**OCP 4.22+ Istio difference:** On OCP 4.22+, the ingress operator installs Istio via Helm, NOT via an OLM Subscription. `servicemeshoperator3` is NOT needed. Instead, two images must be added to `additionalImages` in the ImageSetConfiguration:
- `registry.redhat.io/openshift-service-mesh/istio-pilot-rhel9`
- `registry.redhat.io/openshift-service-mesh/istio-proxyv2-rhel9`

#### Example Subscription YAML (cert-manager)

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager-operator
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: cert-manager-operator-og
  namespace: cert-manager-operator
spec:
  targetNamespaces:
    - cert-manager-operator
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-cert-manager-operator
  namespace: cert-manager-operator
spec:
  name: openshift-cert-manager-operator
  channel: stable-v1
  source: <YOUR_MIRRORED_CATALOG_NAME>
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
```

Dependency operators use own-namespace scope (`targetNamespaces` pointing to their own namespace).

Wait for each CSV to reach `Succeeded` before installing the next:

```bash
oc get csv -n cert-manager-operator -w
```

---

### Step 9: Install RHOAI Operator

**Where:** High side.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: redhat-ods-operator
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: redhat-ods-operator-og
  namespace: redhat-ods-operator
spec: {}
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec:
  name: rhods-operator
  channel: stable-3.4
  source: <YOUR_MIRRORED_CATALOG_NAME>
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
  startingCSV: rhods-operator.3.4.2
```

**Note:** The RHOAI OperatorGroup uses `spec: {}` (AllNamespaces mode), unlike the dependency operators which use own-namespace scope. This is required because RHOAI manages resources across multiple namespaces.

Wait for the CSV:

```bash
oc get csv -n redhat-ods-operator -w
```

---

### Step 10: Apply DSCInitialization (BEFORE DataScienceCluster)

**Where:** High side. **This step MUST come before Step 11.**

**Why this matters in disconnected:** RHOAI injects an `odh-trusted-ca-bundle` ConfigMap into every namespace it manages. Workbenches, pipeline pods, and model servers mount this ConfigMap — NOT the node trust store from Step 7b. Without the mirror registry's CA in `customCABundle`, anything inside a data science project that talks to the mirror over TLS fails with `x509: certificate signed by unknown authority` — even though the cluster's own image pulls succeed fine.

This is **layer 2** of registry CA trust:
- **Layer 1** (Step 7b): `image.config.openshift.io/cluster` `additionalTrustedCA` → node-level CRI-O image pulls
- **Layer 2** (this step): `DSCInitialization` `customCABundle` → pod-level TLS (workbenches, pipelines, model servers)

```yaml
apiVersion: dscinitialization.opendatahub.io/v1
kind: DSCInitialization
metadata:
  name: default-dsci
spec:
  applicationsNamespace: redhat-ods-applications
  monitoring:
    managementState: Managed
    namespace: redhat-ods-monitoring
  trustedCABundle:
    managementState: Managed
    customCABundle: |
      -----BEGIN CERTIFICATE-----
      <contents of your mirror registry CA PEM file>
      -----END CERTIFICATE-----
```

Wait for DSCI to be Ready:

```bash
oc wait --for=jsonpath='{.status.phase}'=Ready \
  dscinitialization/default-dsci --timeout=15m
```

---

### Step 11: Apply DataScienceCluster (v2 API)

**Where:** High side. **Only after Step 10 DSCI is Ready.**

#### Why v2, not v1

RHOAI 3.x serves both v1 and v2 of the DataScienceCluster API; v2 is the storage version. v1 is accepted and silently converted, so it LOOKS like it works. But:

- v1 cannot express `trainer`, `sparkoperator`, or `mlflowoperator` — these components did not exist when v1 was defined
- Whatever v1 cannot say, the operator defaults — `trainer` defaults to `Managed`
- `trainer: Managed` requires the JobSet operator, which is NOT in the mirror set
- The DSC never reaches Ready

#### Field name changes in v2

- `datasciencepipelines` (v1) → `aipipelines` (v2)
- v2 drops `codeflare` and `modelmeshserving` (removed from product)

#### Set every component explicitly

An omitted component takes the operator default, which can change between z-streams. Use `Removed`, not omission.

```yaml
apiVersion: datasciencecluster.opendatahub.io/v2
kind: DataScienceCluster
metadata:
  name: default-dsc
spec:
  components:
    dashboard:
      managementState: Managed
    workbenches:
      managementState: Managed
    kserve:
      managementState: Managed
      rawDeploymentServiceConfig: Headless
    aipipelines:
      managementState: Managed
    modelregistry:
      managementState: Managed
      registriesNamespace: rhoai-model-registries
    # Set ALL unused components to Removed explicitly
    trainer:
      managementState: Removed
    trainingoperator:
      managementState: Removed
    kueue:
      managementState: Removed
    ray:
      managementState: Removed
    sparkoperator:
      managementState: Removed
    trustyai:
      managementState: Removed
    mlflowoperator:
      managementState: Removed
    feastoperator:
      managementState: Removed
    llamastackoperator:
      managementState: Removed
```

**Note on KServe:** v2 accepts ONLY `managementState`, `modelsAsService`, `nim`, `rawDeploymentServiceConfig`, and `wva`. The `serving:` block and `defaultDeploymentMode` from v1/2.x were REMOVED in 3.x — setting them is rejected by the CRD.

Wait for the DSC:

```bash
oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
# Must be "True"
```

---

### Step 12: Verify

Run these checks in order.

#### Mirror configuration

```bash
# OperatorHub default sources disabled
oc get operatorhub cluster -o jsonpath='{.spec.disableAllDefaultSources}'  # must be "true"

# Trusted CA configured
oc get image.config.openshift.io/cluster -o jsonpath='{.spec.additionalTrustedCA.name}'

# IDMS exists
oc get imagedigestmirrorset

# All MachineConfigPools updated (not still rebooting from IDMS apply)
oc get mcp  # UPDATED=True, UPDATING=False, DEGRADED=False

# All CatalogSources READY
oc get catalogsource -n openshift-marketplace
```

#### Operators

```bash
# All CSVs Succeeded
oc get csv -A | grep -v Succeeded

# No stuck CSVs
oc get csv -A -o json | jq '[.items[] | select(.status.phase=="Failed")] | length'
```

#### RHOAI

```bash
# DSCI Ready (check phase, NOT condition — RHOAI 3.4.2 has no Ready condition on DSCI)
oc get dscinitialization default-dsci -o jsonpath='{.status.phase}'  # must be "Ready"

# DSC Ready
oc get datasciencecluster default-dsc -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'  # must be "True"

# odh-trusted-ca-bundle exists (critical for workbenches in disconnected)
oc get configmap odh-trusted-ca-bundle -n redhat-ods-applications

# GatewayClass accepted (for Data Science Gateway)
oc get gatewayclass data-science-gateway-class -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}'

# Dashboard route exists
oc get route rhods-dashboard -n redhat-ods-applications
```

#### Disconnected integrity

```bash
# NO ImagePullBackOff or ErrImagePull ANYWHERE
oc get pods -A -o json | jq '[.items[].status.containerStatuses[]? | select(.state.waiting.reason=="ImagePullBackOff" or .state.waiting.reason=="ErrImagePull")] | length'  # must be 0

# No stuck pods in openshift-marketplace (indicates default catalogs still enabled)
oc get pods -n openshift-marketplace | grep -cE 'ImagePullBackOff|ErrImagePull'
```

---

## Troubleshooting

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| Mirror ends "148/150 copied" with no .tar | 9 GB InstructLab layer hit image timeout | Set `--image-timeout 60m`, re-run (incremental) |
| "invalid default channel configuration for package X" | Filtered to one channel without `defaultChannel` | Add `defaultChannel:` to each package |
| Push fails 403 on a catalog (disconnected) | ImageSetConfiguration no longer matches archive | Digest-pin BEFORE mirroring, never edit after |
| "Manifest list must be converted … Instructed to preserve digests" | `--remove-signatures` passed to push (belongs only on mirror-to-disk) | Remove `--remove-signatures` from push command |
| "reading signatures: .sig … name unknown" | NVIDIA partner registry has no sigstore signature | Add `--remove-signatures` to mirror-to-disk only |
| DSC not Ready, no pods, "no matches for kind DestinationRule" | Istio missing (OCP 4.19-4.21: OSSM 3 not mirrored) | Mirror servicemeshoperator3 |
| DSC not Ready, zero pods (OCP 4.22+) | Two Istio images not mirrored for Helm-based install | Add istio-pilot-rhel9 + istio-proxyv2-rhel9 to additionalImages |
| Dashboard answers "Application is not available" | GatewayClass not accepted — Sail Operator missing | Install OSSM 3 or verify Helm-based Istio images |
| DSC blocked on trainer (not in your manifest) | Applied v1 DSC API; trainer defaults to Managed | Use v2 API with explicit `trainer: Removed` |
| Workbench ImagePullBackOff | Workbench images not in additionalImages | Fetch from rhoai-disconnected-install-helper |
| x509 certificate error in workbench/pipeline pod | DSCI missing customCABundle for mirror CA | Apply DSCI with mirror CA in trustedCABundle |
| "constraints not satisfiable: no operators found with name servicemeshoperator3.v3.1.0" | Ingress operator pins specific OSSM version not in mirror | Pin `SERVICE_MESH3_VERSION` or use `redhat-operators` alias |
| Host unreachable after push | Root filesystem full (Quay used $HOME not --quayStorage) | Serial console recovery, free space |
| "pull QPS exceeded" | kubelet throttling | Self-heals; real mirror gap shows "manifest unknown" |
| imageID shows quay.io on mirrored cluster | Normal — CRI-O records canonical source digest | Not a problem; IDMS redirects at pull time |

---

## Key Differences by OCP Version

| Aspect | OCP 4.19-4.21 | OCP 4.22+ |
|--------|:------------:|:---------:|
| Service Mesh | OLM Subscription for `servicemeshoperator3` | Helm-based via ingress operator |
| Istio images | Mirrored via operator bundle | Two images must be manually added to additionalImages |
| `redhat-operators` alias | Load-bearing (ingress operator needs it) | No longer needed (no Subscription) |
| GatewayAPIWithoutOLM feature gate | Off (default) | On (default) |
| Istio CRDs | Installed by OSSM 3 operator | Installed by ingress operator |

---

## Safety Constraints

- **Never** suggest `--continue-on-error` — partial mirrors cause silent failures downstream
- **Never** skip CA configuration — both layers (node trust AND DSCI customCABundle) are required
- **Never** assume network access — every command that contacts a registry must be explicitly placed on the correct side of the air gap
- **Always** verify mirror completeness before deploying operators — a missing image causes indefinite `ImagePullBackOff`
- **Always** apply DSCI before DSC — reversing the order causes x509 errors in workbenches and pipelines
- **Never** embed registry credentials in YAML files or Git repositories — use Kubernetes secrets and the global pull secret exclusively

---

## References

- [disconnected-rhoai repo](https://github.com/rh-aiservices-bu/disconnected-rhoai) — battle-tested scripts and worked examples
- [rhoai-disconnected-install-helper](https://github.com/red-hat-data-services/rhoai-disconnected-install-helper) — auto-updated workbench image lists
- [RHOAI 3.5 disconnected docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/installing_and_uninstalling_openshift_ai_self-managed_in_a_disconnected_environment/)
- [oc-mirror v2 docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/disconnected_environments/about-installing-oc-mirror-v2)
- [ai-accelerator](https://github.com/redhat-ai-services/ai-accelerator) — GitOps-based RHOAI deployment framework

---

## Output Format

For each step, produce the exact command or YAML the user should run, prefixed with where to run it (low side or high side). For template-based steps, show the file path and the specific placeholders to replace. At the end, produce a summary:

```
# Disconnected RHOAI Deployment Summary

## Environment
- OCP Version: {version}
- RHOAI Version: {version}
- Mirror Registry: {registry URL}
- Deployment Method: {CLI / GitOps}

## Steps Completed
1. Mirror registry installed: {hostname}:8443
2. Images mirrored: {count} operator + {count} workbench
3. Cluster configured: IDMS, ITMS, CatalogSources, pull secret, CA trust
4. Operators installed: cert-manager, OSSM3/Istio, NFD, GPU, RHOAI
5. DSCI applied with customCABundle: Ready
6. DSC v2 applied: Ready

## Verification
- DSCI: {Ready/Not Ready}
- DSC: {Ready/Not Ready}
- GatewayClass: {Accepted/Not Accepted}
- ImagePullBackOff pods: {count}
- Dashboard URL: {URL}
```

## Related Skills

- [`rhoai-install-validator`](../rhoai-install-validator/) — Post-deployment validation and health checking
- [`rhoai-upgrade-advisor`](../../administer/rhoai-upgrade-advisor/) — Upgrade readiness assessment
- [`gitops-config-generator`](../gitops-config-generator/) — Generate Kustomize patches and ArgoCD Applications
- [`rhoai-disconnected-helper`](../rhoai-disconnected-helper/) — Diagnose mirror configuration and image pull issues
