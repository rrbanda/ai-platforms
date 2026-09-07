# 09 — Disconnected RHOAI Deployment Reference

> Ground-truth step-by-step procedure for deploying Red Hat OpenShift AI on a disconnected OpenShift cluster.
> Derived from [rh-aiservices-bu/disconnected-rhoai](https://github.com/rh-aiservices-bu/disconnected-rhoai) (verified end-to-end on OCP 4.20.30 / RHOAI 3.4.2 and OCP 4.22.8 / RHOAI 3.4.3) and the official RHOAI 3.5 disconnected installation documentation.
> Last updated: 2026-08-22

---

## Assumptions

- OpenShift 4.19+ is already installed and running
- You have cluster-admin access
- A connected host (low side / jump box) has internet access
- A disconnected host (high side / bastion) can reach the cluster but not the internet
- Content crosses the air gap via rsync/sneakernet

---

## Storage Sizing (Critical)

The RHOAI mirror is **~517 GB** (171 operator images + 63 workbench images). Three copies exist simultaneously during the push phase.

| Host | Holds | Measured | Volume Required |
|------|-------|---------|----------------|
| Low side (connected) | Archive + oc-mirror cache | ~1,055 GB | **1,500 GB** |
| High side (disconnected) | Archive + cache + Quay storage | ~1,650 GB | **2,000 GB** |

---

## Step 1: Install Mirror Registry

**Where:** High side (disconnected host).

Install the mirror registry for Red Hat OpenShift (streamlined Quay) on port 8443.

```bash
tar -xzf mirror-registry-amd64.tar.gz -C ~/
./mirror-registry install \
  --quayHostname $(hostname -f) \
  --quayRoot /home/$USER/quay-install \
  --quayStorage /mnt/mirror/quay-storage
```

**Critical:** `--quayStorage` MUST point to the large volume, not `$HOME`. Without it, Quay uses a rootless podman volume on the root filesystem. A 500 GB push fills a 299 GB root disk, and at zero bytes free `dhclient` cannot write a lease — the host reboots with no network.

**Critical:** `--quayHostname` must be a FQDN that resolves from the cluster nodes, not just from the bastion.

Trust the CA:

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

## Step 2: Configure Authentication

**Where:** Low side (for mirroring), High side (for pushing).

Seed the container auth file with your Red Hat pull secret:

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

## Step 3: Generate ImageSetConfiguration

**Where:** Low side (connected host).

**Critical — Digest-pin the catalog images BEFORE mirroring.** The configuration must match what was recorded when the archive was built. Editing it afterwards — even just swapping a tag for its digest — makes `oc-mirror` fall back to the network during the push, which fails 403 on the disconnected host.

Resolve the catalog digest:

```bash
OCP_VERSION=4.20
skopeo inspect --raw docker://registry.redhat.io/redhat/redhat-operator-index:v${OCP_VERSION} \
  | jq -r '.manifests[] | select(.platform.architecture=="amd64") | .digest'
```

**Critical — `defaultChannel` is REQUIRED** on every filtered package. Without it, oc-mirror emits "invalid default channel configuration" and refuses to generate the catalog.

### Real ImageSetConfiguration (from verified deployment)

```yaml
apiVersion: mirror.openshift.io/v2alpha1
kind: ImageSetConfiguration
mirror:
  operators:
    - catalog: registry.redhat.io/redhat/redhat-operator-index@sha256:<PINNED_DIGEST>
      packages:
        - name: rhods-operator
          defaultChannel: stable-3.4    # MUST match channel name
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
    # 63 workbench images — see Step 3a
```

### Step 3a: The 63 images oc-mirror CANNOT find

**Why:** Workbench and notebook images are referenced through runtime ImageStreams created by the RHOAI operator, NOT from the operator bundle's `relatedImages`. Without them, RHOAI installs and the dashboard loads, but creating a workbench fails with `ImagePullBackOff`.

Fetch the version-matched list:

```bash
curl -sfL https://raw.githubusercontent.com/red-hat-data-services/rhoai-disconnected-install-helper/main/rhoai-<VERSION>.md \
  | awk '/^# Additional images/{a=1; next} /^# (Unsupported|ImageSetConfiguration)/{a=0} a' \
  | grep -oE '(quay\.io|registry\.redhat\.io)[^ ]+@sha256:[a-f0-9]+' | sort -u
```

The helper repo tries `rhoai-<x.y.z>.md` then falls back to `rhoai-<x.y>.md`. Add these to the `additionalImages` section.

**Budget an extra 100-200 GB for these images.**

---

## Step 4: Mirror to Disk

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

**For NVIDIA images:** Add `--remove-signatures` to the mirror-to-disk command (NOT to the push). The NVIDIA partner registry on `registry.connect.redhat.com` has no published sigstore signature, and one failing image fails the entire run.

This takes **~8 hours** for the RHOAI batch. Monitor progress by watching the archive file size, not the log:

```bash
ls -l /mnt/mirror/criab-mirror/*.tar; sleep 30; ls -l /mnt/mirror/criab-mirror/*.tar
```

---

## Step 5: Transfer Across the Air Gap

**Where:** Low side → High side.

```bash
rsync -a --partial --info=progress2 \
  -e "ssh -o StrictHostKeyChecking=no" \
  /mnt/mirror/criab-mirror/mirror_*.tar \
  /mnt/mirror/criab-mirror/imageset-config.yaml \
  /mnt/mirror/criab-mirror/tools/ \
  ${USER}@${HIGH_IP}:/mnt/mirror/criab-mirror/
```

Verify sizes match on both sides — for a 500 GB payload, checksums cost hours and rsync already verifies every block in transit.

---

## Step 6: Push to Mirror Registry

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

**Do NOT pass `--remove-signatures` on the push.** It belongs only on the mirror-to-disk phase. On the push, it blocks manifest rewriting and takes the entire rhods-operator bundle down.

This emits cluster resources under `working-dir/cluster-resources/`:

| File | Kind | Purpose |
|------|------|---------|
| `idms-oc-mirror.yaml` | ImageDigestMirrorSet | Digest pull redirection |
| `itms-oc-mirror.yaml` | ImageTagMirrorSet | Tag pull redirection |
| `cs-*.yaml` | CatalogSource | The mirrored catalogs |

**Never hand-write these** — they must match what was actually mirrored.

---

## Step 7: Configure the Cluster for the Mirror

**Where:** High side, logged into the cluster.

### 7a. Add mirror registry credentials to global pull secret

```bash
oc get secret/pull-secret -n openshift-config \
  --template='{{index .data ".dockerconfigjson" | base64decode}}' > /tmp/ps.json
oc registry login --registry="$MIRROR_REGISTRY" \
  --auth-basic="init:$MIRROR_REGISTRY_PASSWORD" --to=/tmp/ps.json
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=/tmp/ps.json
```

### 7b. Trust the registry CA cluster-wide

```bash
oc create configmap registry-cas -n openshift-config \
  --from-file="${MIRROR_REGISTRY_FQDN}..8443=${MIRROR_REGISTRY_CA_FILE}" \
  --dry-run=client -o yaml | oc apply -f -
oc patch image.config.openshift.io/cluster --type=merge \
  -p '{"spec":{"additionalTrustedCA":{"name":"registry-cas"}}}'
```

The `..8443` in the key is not a typo — a literal `..` encodes the port separator in OpenShift's trusted CA config.

### 7c. Apply IDMS and ITMS (this reboots every node)

```bash
oc apply -f working-dir/cluster-resources/idms-oc-mirror.yaml
oc apply -f working-dir/cluster-resources/itms-oc-mirror.yaml
oc get mcp -w   # Wait for UPDATED=True, UPDATING=False on all pools
```

**NOT ICSP.** oc-mirror v2 generates ImageDigestMirrorSet and ImageTagMirrorSet. ICSP is deprecated.

### 7d. Disable default OperatorHub catalogs

```bash
oc patch OperatorHub cluster --type=merge \
  -p '{"spec":{"disableAllDefaultSources":true}}'
```

### 7e. Apply mirrored CatalogSources

```bash
oc apply -f working-dir/cluster-resources/cs-*.yaml
```

### 7f. Create `redhat-operators` CatalogSource alias

**Why:** The ingress operator auto-creates a Subscription for `servicemeshoperator3` against the name `redhat-operators` and reconciles it. Without this alias, OSSM 3 never installs.

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

---

## Step 8: Install Dependency Operators

**Where:** High side. **Order matters.**

Each operator follows the pattern: Namespace → OperatorGroup → Subscription. The CatalogSource name is generated by oc-mirror (e.g., `cs-redhat-operator-index-sha256-8d67e`). Find yours:

```bash
oc get catalogsource -n openshift-marketplace -o name
```

### Installation order

| # | Package | Namespace | Channel | Catalog | Why First |
|---|---------|-----------|---------|---------|-----------|
| 1 | `openshift-cert-manager-operator` | `cert-manager-operator` | `stable-v1` | redhat-operator-index | RHOAI 3.x will not reconcile without it |
| 2 | `servicemeshoperator3` | `openshift-operators` | `stable` | redhat-operator-index | Data Science Gateway (OCP 4.19-4.21 only) |
| 3 | `nfd` | `openshift-nfd` | `stable` | redhat-operator-index | Labels GPU nodes for NVIDIA operator |
| 4 | `gpu-operator-certified` | `nvidia-gpu-operator` | `stable` | certified-operator-index | GPU drivers (optional, harmless without GPU nodes) |

**OCP 4.22+ Istio difference:** On OCP 4.22+, the ingress operator installs Istio via Helm, NOT via an OLM Subscription. `servicemeshoperator3` is NOT needed. Instead, two images must be added to `additionalImages` manually:
- `registry.redhat.io/openshift-service-mesh/istio-pilot-rhel9`
- `registry.redhat.io/openshift-service-mesh/istio-proxyv2-rhel9`

### Example Subscription YAML

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

Wait for each CSV to reach `Succeeded` before installing the next:

```bash
oc get csv -n cert-manager-operator -w
```

---

## Step 9: Install RHOAI Operator

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

**Note:** The RHOAI OperatorGroup uses `spec: {}` (AllNamespaces mode), unlike the dependency operators which use own-namespace scope.

---

## Step 10: Apply DSCInitialization (BEFORE DataScienceCluster)

**Where:** High side.

**Why this matters in disconnected:** RHOAI injects an `odh-trusted-ca-bundle` ConfigMap into every namespace it manages. Workbenches, pipeline pods, and model servers mount this ConfigMap. Without the mirror registry's CA in `customCABundle`, anything inside a data science project that talks to the mirror over TLS fails with `x509: certificate signed by unknown authority` — even though the cluster's own image pulls succeed (those use the node trust store from Step 7b, which pods do NOT mount).

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

## Step 11: Apply DataScienceCluster (v2 API)

**Where:** High side.

**Critical — Use v2 API, not v1.** RHOAI 3.x serves both v1 and v2; v2 is the storage version. v1 is accepted and converted, so it LOOKS like it works. But v1 cannot express `trainer`, `sparkoperator`, or `mlflowoperator` — these components didn't exist when v1 was defined. Whatever v1 cannot say, the operator defaults. `trainer` defaults to `Managed` and requires the JobSet operator, which is NOT in the mirror set. The DSC never reaches Ready.

**Critical — Set every component explicitly.** An omitted component takes the operator default, which can change between z-streams. Use `Removed`, not omission.

**Critical — Field name change:** `datasciencepipelines` in v1 is `aipipelines` in v2.

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

---

## Step 12: Verify

Run these checks in order:

### Mirror configuration

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

### Operators

```bash
# All CSVs Succeeded
oc get csv -A | grep -v Succeeded

# No stuck CSVs
oc get csv -A -o json | jq '[.items[] | select(.status.phase=="Failed")] | length'
```

### RHOAI

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

### Disconnected integrity

```bash
# NO ImagePullBackOff or ErrImagePull ANYWHERE
oc get pods -A -o json | jq '[.items[].status.containerStatuses[]? | select(.state.waiting.reason=="ImagePullBackOff" or .state.waiting.reason=="ErrImagePull")] | length'  # must be 0

# No stuck pods in openshift-marketplace (indicates default catalogs still enabled)
oc get pods -n openshift-marketplace | grep -cE 'ImagePullBackOff|ErrImagePull'
```

---

## Troubleshooting (from battle-tested deployments)

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

## References

- [disconnected-rhoai repo](https://github.com/rh-aiservices-bu/disconnected-rhoai) — battle-tested scripts and worked examples
- [rhoai-disconnected-install-helper](https://github.com/red-hat-data-services/rhoai-disconnected-install-helper) — auto-updated workbench image lists
- [RHOAI 3.5 disconnected docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/installing_and_uninstalling_openshift_ai_self-managed_in_a_disconnected_environment/)
- [oc-mirror v2 docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/disconnected_environments/about-installing-oc-mirror-v2)
- [ai-accelerator](https://github.com/redhat-ai-services/ai-accelerator) — GitOps-based RHOAI deployment framework
