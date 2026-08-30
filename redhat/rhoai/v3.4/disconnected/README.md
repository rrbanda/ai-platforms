# RHOAI 3.4 -- Disconnected / Air-Gapped Deployment

This guide walks you through deploying Red Hat OpenShift AI (RHOAI) 3.4 on a fully disconnected (air-gapped) OpenShift cluster using this GitOps repository. It covers mirroring all required operator and workload images to an internal registry, configuring the cluster to pull from that registry, and deploying via ArgoCD. No prior disconnected-deployment experience is assumed.

---

## Prerequisites Checklist

| Requirement | Details |
|---|---|
| **Connected host** (for mirroring) | RHEL 9+ or Fedora with `oc-mirror` v2 **or** `skopeo` installed, **800 GB+** free disk, authenticated to `registry.redhat.io` via `podman login` or `~/.docker/config.json` |
| **Disconnected cluster** | OpenShift Container Platform **4.19+**, internal container registry (e.g. Quay, Harbor, Nexus, or mirror-registry), `cluster-admin` access |
| **Transfer medium** | USB drive, portable SSD, or network relay capable of moving **~400–800 GB** across the air gap (skip if a DMZ relay exists) |
| **CLI tools** | `oc` (4.19+), `oc-mirror` v2 (or `skopeo` 1.14+), `kubeseal`, `helm` (optional, for chart customization) |
| **Pull secret** | Combined pull secret from [console.redhat.com/openshift/install/pull-secret](https://console.redhat.com/openshift/install/pull-secret) merged with your internal registry credentials |
| **Git access** | Fork or clone of this repository, pushable from inside the disconnected environment (or vendored onto the transfer medium) |

---

## Disk Space Requirements

| Component | Estimated Size |
|---|---|
| RHOAI operator bundle + all dependency operators (14 packages) | ~250–300 GB |
| GPU Operator images (NFD + NVIDIA) | ~15–20 GB |
| Workload images (Milvus, etcd, MinIO, PostgreSQL) | ~5–10 GB |
| Certified operators (Sealed Secrets) | ~1 GB |
| **Total (with oc-mirror cache)** | **~400–800 GB** |

> **Tip:** If you exclude the optional observability stack (COO, Tempo, OTel) and GPU operators, the footprint drops to ~150–200 GB.

---

## Path A: Using oc-mirror v2 (Recommended)

`oc-mirror` v2 is the recommended tool for mirroring operator catalogs and images. It generates the cluster resources (IDMS, CatalogSource) automatically.

### Step 1 -- Prepare the ImageSetConfiguration

Copy the provided template and fill in the placeholders.

```bash
cd redhat/rhoai/v3.4/disconnected

cp imageset-config-template.yaml imageset-config.yaml
```

Edit `imageset-config.yaml` and replace the three placeholders:

| Placeholder | Value for RHOAI 3.4 |
|---|---|
| `REPLACE_OCP_VERSION` | `v4.19` (match your cluster's minor version) |
| `REPLACE_RHOAI_CHANNEL` | `stable-3.4` |
| `REPLACE_KUEUE_CHANNEL` | `stable-v1.2` |

```bash
sed -i \
  -e 's/REPLACE_OCP_VERSION/v4.19/g' \
  -e 's/REPLACE_RHOAI_CHANNEL/stable-3.4/g' \
  -e 's/REPLACE_KUEUE_CHANNEL/stable-v1.2/g' \
  imageset-config.yaml
```

**Verify:** Open `imageset-config.yaml` and confirm all `REPLACE_*` strings are gone.

### Step 2 -- Mirror to a local archive

On the **connected host**, run `oc-mirror` to download everything into a local directory:

```bash
oc mirror --config imageset-config.yaml \
  file:///home/<YOUR_USER>/mirror-archive \
  --v2
```

This downloads all operator catalog indexes and referenced images. Expect this to take **2–6 hours** depending on bandwidth. Output lands in `mirror-archive/` and a `working-dir/` directory with cluster-resources.

**Verify:** Check that `working-dir/cluster-resources/` contains IDMS and CatalogSource YAML files.

### Step 3 -- Transfer the archive across the air gap

Copy the entire `mirror-archive/` directory and `working-dir/` to your transfer medium:

```bash
tar -cf rhoai-mirror.tar mirror-archive/ working-dir/
# Copy rhoai-mirror.tar to USB drive or portable SSD
```

On the disconnected side, extract:

```bash
tar -xf rhoai-mirror.tar
```

### Step 4 -- Push images to the internal registry

From a host that can reach your internal registry:

```bash
oc mirror --from file:///path/to/mirror-archive \
  docker://<INTERNAL_REGISTRY_URL> \
  --v2
```

Replace `<INTERNAL_REGISTRY_URL>` with your internal registry (e.g. `registry.example.com:5000`).

**Verify:** Log in to your registry UI or run `curl -s https://<INTERNAL_REGISTRY_URL>/v2/_catalog | jq .` to confirm images are present.

### Step 5 -- Apply generated IDMS and CatalogSource

`oc-mirror` generates the cluster resources you need. Apply them:

```bash
oc apply -f working-dir/cluster-resources/
```

This creates:
- **ImageDigestMirrorSet (IDMS):** tells the cluster to pull images from your internal registry instead of `registry.redhat.io`
- **CatalogSource(s):** points OLM to the mirrored catalog indexes

**Note the CatalogSource name(s)** -- you will need them later (e.g. `cs-redhat-operator-index-v4-19`, `cs-certified-operator-index-v4-19`). Find them with:

```bash
oc get catalogsource -n openshift-marketplace
```

### Step 6 -- Disable default OperatorHub catalogs

Prevent the cluster from trying to reach the internet for operator catalogs:

```bash
oc patch operatorhub cluster --type merge \
  -p '{"spec":{"disableAllDefaultSources":true}}'
```

**Verify:**

```bash
oc get operatorhub cluster -o jsonpath='{.spec.disableAllDefaultSources}'
# Should output: true
```

### Step 7 -- Mirror additional workload images

The operator catalog mirror covers operators, but some workload images deployed by RHOAI are **not** included in the operator bundle. Mirror these separately:

| Image | Used By | Notes |
|---|---|---|
| `milvusdb/milvus:v2.6.0` | Milvus vector database | AutoRAG workload |
| `quay.io/coreos/etcd:v3.5.5` | etcd (Milvus dependency) | |
| `quay.io/minio/minio:RELEASE.2023-09-04T19-57-37Z` | MinIO (DSPA built-in storage) | |
| `registry.redhat.io/rhel9/postgresql-15:latest` | PostgreSQL (MaaS backend) | |

You can add these to the `imageset-config.yaml` under `additionalImages` and re-run, or mirror them individually with `skopeo`:

```bash
for img in \
  "docker://milvusdb/milvus:v2.6.0" \
  "docker://quay.io/coreos/etcd:v3.5.5" \
  "docker://quay.io/minio/minio:RELEASE.2023-09-04T19-57-37Z" \
  "docker://registry.redhat.io/rhel9/postgresql-15:latest"; do

  skopeo copy --all \
    "${img}" \
    "docker://<INTERNAL_REGISTRY_URL>/$(echo ${img} | sed 's|docker://||')"
done
```

Alternatively, add to your `imageset-config.yaml`:

```yaml
mirror:
  additionalImages:
    - name: milvusdb/milvus:v2.6.0
    - name: quay.io/coreos/etcd:v3.5.5
    - name: quay.io/minio/minio:RELEASE.2023-09-04T19-57-37Z
    - name: registry.redhat.io/rhel9/postgresql-15:latest
```

### Step 8 -- Bootstrap GitOps and Sealed Secrets

The bootstrap subscriptions need to point to your mirrored catalogs. Edit the subscription sources before applying:

```bash
cd redhat/rhoai/v3.4/setup/bootstrap

# Update GitOps operator subscription to use mirrored catalog
sed -i 's/source: redhat-operators/source: <REDHAT_CATALOG_NAME>/g' \
  gitops-operator-subscription.yaml

# Update Sealed Secrets subscription to use mirrored catalog
sed -i 's/source: certified-operators/source: <CERTIFIED_CATALOG_NAME>/g' \
  sealed-secrets-subscription.yaml
```

Replace `<REDHAT_CATALOG_NAME>` and `<CERTIFIED_CATALOG_NAME>` with the CatalogSource names from Step 5.

Apply the bootstrap:

```bash
oc apply -k redhat/rhoai/v3.4/setup/bootstrap/
```

Wait for both operators to install:

```bash
oc get csv -n openshift-gitops-operator --watch
oc get csv -n sealed-secrets --watch
```

### Step 9 -- Switch to disconnected profiles, seal secrets, and deploy

See [After Mirroring (Common Steps)](#after-mirroring-common-steps) below.

---

## Path B: Using skopeo (Manual Pull + Push)

For organizations that cannot or prefer not to use `oc-mirror`. This path requires more manual steps but gives full control over what is mirrored.

### Step 1 -- Identify images to mirror

Review the operator packages listed in the ImageSetConfiguration template:

```bash
cat redhat/rhoai/v3.4/disconnected/imageset-config-template.yaml
```

The template lists **14 operator packages** across two catalog indexes:
- `redhat-operator-index`: servicemeshoperator3, rhods-operator, openshift-cert-manager-operator, rhcl-operator, leader-worker-set, job-set, kueue-operator, openshift-custom-metrics-autoscaler-operator, cluster-observability-operator, opentelemetry-product, tempo-product, nfd, gpu-operator-certified
- `certified-operator-index`: sealed-secrets-operator-helm

### Step 2 -- Mirror the Red Hat operator catalog index

```bash
oc adm catalog mirror \
  registry.redhat.io/redhat/redhat-operator-index:v4.19 \
  <INTERNAL_REGISTRY_URL> \
  --filter-by-os="linux/amd64" \
  --index-filter-by-os="linux/amd64" \
  --to-manifests=./redhat-catalog-manifests
```

This generates ICSP/IDMS manifests and a `mapping.txt` file in `./redhat-catalog-manifests/`.

### Step 3 -- Mirror the Certified operator catalog index

```bash
oc adm catalog mirror \
  registry.redhat.io/redhat/certified-operator-index:v4.19 \
  <INTERNAL_REGISTRY_URL> \
  --filter-by-os="linux/amd64" \
  --index-filter-by-os="linux/amd64" \
  --to-manifests=./certified-catalog-manifests
```

### Step 4 -- Mirror individual images using skopeo (for air gap)

If your connected host cannot reach the internal registry directly, pull images to a local directory first:

```bash
# Pull catalog and operator images to local directory
skopeo copy --all \
  docker://registry.redhat.io/redhat/redhat-operator-index:v4.19 \
  dir:///home/<YOUR_USER>/mirror/redhat-operator-index

# Repeat for each operator image listed in mapping.txt
while IFS='=' read -r src dst; do
  skopeo copy --all "docker://${src}" "dir:///home/<YOUR_USER>/mirror/$(echo ${src} | tr '/:' '_')"
done < ./redhat-catalog-manifests/mapping.txt
```

> **Warning:** This can take a very long time. Consider using `oc-mirror` (Path A) instead for large mirrors.

### Step 5 -- Transfer the mirror directory across the air gap

```bash
tar -cf rhoai-skopeo-mirror.tar mirror/
# Copy to USB drive or portable SSD, then extract on disconnected side
```

### Step 6 -- Push images from local directory to internal registry

```bash
# Push catalog index
skopeo copy --all \
  dir:///path/to/mirror/redhat-operator-index \
  docker://<INTERNAL_REGISTRY_URL>/redhat/redhat-operator-index:v4.19

# Push operator images from mapping.txt
while IFS='=' read -r src dst; do
  local_dir="$(echo ${src} | tr '/:' '_')"
  skopeo copy --all \
    "dir:///path/to/mirror/${local_dir}" \
    "docker://${dst}"
done < ./redhat-catalog-manifests/mapping.txt
```

Repeat the same process for the certified catalog manifests.

### Step 7 -- Create and apply IDMS and CatalogSource resources

Create an ImageDigestMirrorSet from the generated manifests:

```bash
oc apply -f ./redhat-catalog-manifests/imageDigestMirrorSet.yaml
oc apply -f ./certified-catalog-manifests/imageDigestMirrorSet.yaml
```

Create CatalogSource resources for each mirrored catalog:

```yaml
# redhat-catalog-source.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: <REDHAT_CATALOG_NAME>
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: <INTERNAL_REGISTRY_URL>/redhat/redhat-operator-index:v4.19
  displayName: Red Hat Operators (Mirrored)
  publisher: Red Hat
  updateStrategy:
    registryPoll:
      interval: 30m
```

```yaml
# certified-catalog-source.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: <CERTIFIED_CATALOG_NAME>
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: <INTERNAL_REGISTRY_URL>/redhat/certified-operator-index:v4.19
  displayName: Certified Operators (Mirrored)
  publisher: Red Hat
  updateStrategy:
    registryPoll:
      interval: 30m
```

```bash
oc apply -f redhat-catalog-source.yaml
oc apply -f certified-catalog-source.yaml
```

### Step 8 -- Mirror workload images and disable default catalogs

Mirror the additional workload images (see [Path A, Step 7](#step-7----mirror-additional-workload-images) for the image list).

Disable default catalogs:

```bash
oc patch operatorhub cluster --type merge \
  -p '{"spec":{"disableAllDefaultSources":true}}'
```

### Step 9 -- Bootstrap and deploy

Follow the same bootstrap and deploy procedure as Path A, Steps 8 and 9.

---

## After Mirroring (Common Steps)

Once your images are in the internal registry (from either Path A or Path B), follow these steps to deploy RHOAI.

### 1. Verify IDMS is applied

```bash
oc get imagedigestmirrorset
# You should see one or more IDMS resources
```

### 2. Verify CatalogSources are healthy

```bash
oc get catalogsource -n openshift-marketplace
# Should show your mirrored catalog(s) with READY status
```

Note the exact names -- you will use them in the next steps. Example:
- Red Hat catalog: `cs-redhat-operator-index-v4-19`
- Certified catalog: `cs-certified-operator-index-v4-19`

### 3. Verify default catalogs are disabled

```bash
oc get operatorhub cluster -o jsonpath='{.spec.disableAllDefaultSources}'
# Should output: true
```

### 4. Bootstrap GitOps and Sealed Secrets

If you have not already done so (Step 8 in Path A):

```bash
oc apply -k redhat/rhoai/v3.4/setup/bootstrap/
```

Wait for the operators to be ready:

```bash
oc wait csv --all --for=jsonpath='{.status.phase}'=Succeeded \
  -n openshift-gitops-operator --timeout=300s

oc wait csv --all --for=jsonpath='{.status.phase}'=Succeeded \
  -n sealed-secrets --timeout=300s
```

### 5. Switch to disconnected profiles

Copy the disconnected profile YAMLs into the active application directory:

```bash
cd redhat/rhoai/v3.4

# Platform profile (uses mirrored catalog for OLM)
cp profiles/disconnected/platform.yaml base/applications/rhoai-platform.yaml

# Service Mesh profile
cp profiles/disconnected/servicemesh.yaml base/applications/00-servicemesh.yaml
```

Edit both files -- replace the placeholder with your actual mirrored CatalogSource names:

```bash
# In rhoai-platform.yaml:
#   Replace REPLACE_WITH_MIRRORED_CATALOG_NAME with your Red Hat catalog name
sed -i 's/REPLACE_WITH_MIRRORED_CATALOG_NAME/<REDHAT_CATALOG_NAME>/g' \
  base/applications/rhoai-platform.yaml

# In 00-servicemesh.yaml:
#   If needed, update the subscription source to match your catalog
```

> **v3.4 note:** RHOAI 3.4 uses **LlamaStack** (via `llamastackoperator`) and the **Models as a Service** (`modelsAsService`) component under KServe. This differs from v3.5, which uses OGX.

### 6. Seal secrets

Create and seal any required secrets (e.g. registry credentials):

```bash
# Create the registry secret from template
cp secrets/registry-secret.yaml.template secrets/registry-secret.yaml
# Edit: fill in your registry credentials

# Seal it
kubeseal --format yaml \
  --controller-name sealed-secrets-controller \
  --controller-namespace sealed-secrets \
  < secrets/registry-secret.yaml \
  > base/sealed-secrets/registry-secret.yaml
```

Or use the convenience script:

```bash
./scripts/reseal-all.sh
```

### 7. Commit and push changes

```bash
git add -A
git commit -m "Switch to disconnected profile for RHOAI 3.4"
git push
```

### 8. Deploy the App-of-Apps

```bash
oc apply -f redhat/rhoai/v3.4/base/app-of-apps.yaml
```

ArgoCD will pick up the child applications and begin deploying operators and configuration.

---

## Switching to Disconnected Profile

The disconnected profiles differ from connected profiles in one key way: they set `olm.source` to point at your mirrored CatalogSource instead of the default `redhat-operators`.

```bash
cd redhat/rhoai/v3.4

# Copy disconnected profiles into the active applications directory
cp profiles/disconnected/platform.yaml base/applications/rhoai-platform.yaml
cp profiles/disconnected/servicemesh.yaml base/applications/00-servicemesh.yaml

# Replace placeholders with actual CatalogSource names
sed -i 's/REPLACE_WITH_MIRRORED_CATALOG_NAME/<REDHAT_CATALOG_NAME>/g' \
  base/applications/rhoai-platform.yaml
```

To switch **back** to connected mode:

```bash
cp profiles/connected/platform.yaml base/applications/rhoai-platform.yaml
```

### Inference-Only Profile

If you only need the inference stack (KServe, model serving) without the full platform:

```bash
cp profiles/disconnected/inference-only.yaml base/applications/rhoai-platform.yaml
sed -i 's/REPLACE_WITH_MIRRORED_CATALOG_NAME/<REDHAT_CATALOG_NAME>/g' \
  base/applications/rhoai-platform.yaml
```

---

## Common Pitfalls

1. **ICSP is deprecated -- use IDMS.** `ImageContentSourcePolicy` (ICSP) is deprecated in OCP 4.14+. Always use `ImageDigestMirrorSet` (IDMS) instead. If `oc-mirror` generates ICSP files, you are using v1 -- switch to `--v2`.

2. **oc-mirror v1 vs v2.** v1 is deprecated and generates ICSP. Always pass the `--v2` flag: `oc mirror --v2`. If you see `imageContentSourcePolicy.yaml` in the output, you are on v1.

3. **Two CatalogSources are needed.** Red Hat operators and Certified operators use different catalog indexes (`redhat-operator-index` and `certified-operator-index`). You must mirror and create a CatalogSource for **both** if you use Sealed Secrets from the certified catalog.

4. **Workbench/notebook images are NOT in the operator bundle.** Operator mirrors only include the operator itself. Workload images like Milvus, etcd, MinIO, and PostgreSQL must be mirrored separately via `additionalImages` in the ImageSetConfiguration or manually with `skopeo`.

5. **GPU Operator images are large (~20 GB).** The NFD and GPU operator images are substantial. Ensure sufficient disk space and bandwidth. If you do not need GPU support, remove `nfd` and `gpu-operator-certified` from the `imageset-config.yaml` to save space and time.

6. **CatalogSource name must match the profile YAML.** The value you set for `olm.source` in the disconnected platform profile must exactly match the `metadata.name` of the CatalogSource you created. A mismatch means OLM cannot find the operator packages.

7. **Multi-arch images need the `--all` flag in skopeo.** By default, `skopeo copy` only copies the image for the current architecture. Use `--all` to copy all architectures (important for multi-arch clusters): `skopeo copy --all docker://source docker://dest`.

8. **Disable default OperatorHub catalogs.** If you do not disable the default catalogs with `oc patch operatorhub cluster ...`, OLM may attempt to pull from the internet and fail (or use stale non-mirrored packages).

9. **Sealed Secrets controller image must be mirrored too.** The Sealed Secrets operator is in the `certified-operator-index`. If you forget to mirror this catalog, the Sealed Secrets controller pod will fail with `ImagePullBackOff`.

10. **Registry CA trust.** If your internal registry uses a self-signed certificate, every cluster node must trust the CA. Add the CA bundle to the cluster's `image.config.openshift.io/cluster` resource:

    ```bash
    oc create configmap registry-ca \
      --from-file=<INTERNAL_REGISTRY_URL>=</path/to/ca.crt> \
      -n openshift-config

    oc patch image.config.openshift.io/cluster --type merge \
      -p '{"spec":{"additionalTrustedCA":{"name":"registry-ca"}}}'
    ```

---

## Verification Checklist

Run these commands after deployment to verify everything is working:

```bash
# 1. Check IDMS is applied
oc get imagedigestmirrorset
# Expected: one or more IDMS resources listed

# 2. Check CatalogSources are present and healthy
oc get catalogsource -n openshift-marketplace
# Expected: your mirrored catalog(s) with READY status

# 3. Check operators are available in the mirrored catalog
oc get packagemanifest | grep -E "rhods|servicemesh|cert-manager|sealed-secrets"
# Expected: packages listed with your mirrored catalog as the source

# 4. Check no pods have image pull errors
oc get pods -A | grep -E "ImagePull|ErrImage"
# Expected: no output (no pull errors)

# 5. Check GitOps operator is running
oc get csv -n openshift-gitops-operator
# Expected: openshift-gitops-operator CSV in Succeeded phase

# 6. Check Sealed Secrets operator is running
oc get csv -n sealed-secrets
# Expected: sealed-secrets CSV in Succeeded phase

# 7. Check ArgoCD applications are synced
oc get applications.argoproj.io -n openshift-gitops
# Expected: all applications show Synced/Healthy

# 8. Check DataScienceCluster status
oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}'
# Expected: Ready

# 9. Check RHOAI dashboard is accessible
oc get route -n redhat-ods-applications
# Expected: rhods-dashboard route with a valid URL
```

---

## File Reference

Files in this repository relevant to disconnected deployment of RHOAI 3.4:

| File | Purpose |
|---|---|
| `disconnected/imageset-config-template.yaml` | ImageSetConfiguration template for `oc-mirror` v2 -- lists all operator packages and channels to mirror |
| `profiles/disconnected/platform.yaml` | Full platform ArgoCD Application with `olm.source` set to placeholder for mirrored catalog |
| `profiles/disconnected/inference-only.yaml` | Inference-only ArgoCD Application with `olm.source` set to placeholder for mirrored catalog |
| `profiles/disconnected/servicemesh.yaml` | Service Mesh ArgoCD Application for disconnected environments |
| `profiles/connected/platform.yaml` | Connected equivalent (for reference / switching back) |
| `setup/bootstrap/gitops-operator-subscription.yaml` | GitOps operator Subscription (update `source` for disconnected) |
| `setup/bootstrap/sealed-secrets-subscription.yaml` | Sealed Secrets operator Subscription (update `source` for disconnected) |
| `base/app-of-apps.yaml` | Top-level ArgoCD Application that deploys all child apps |
| `base/applications/rhoai-platform.yaml` | Active platform Application (overwritten by profile copy) |
| `base/applications/00-servicemesh.yaml` | Active Service Mesh Application (overwritten by profile copy) |
| `secrets/registry-secret.yaml.template` | Template for registry pull secret |
| `scripts/reseal-all.sh` | Convenience script to seal all secrets with `kubeseal` |

---

## Version-Specific Notes for RHOAI 3.4

- **LlamaStack:** RHOAI 3.4 uses the **LlamaStack** operator (`llamastackoperator`) for agentic AI workloads. This is replaced by OGX in v3.5.
- **Models as a Service:** v3.4 exposes MaaS through `modelsAsService` under the KServe component. In v3.5 this moves to the `aigateway` component.
- **Channel:** Use `stable-3.4` for the RHOAI operator channel.
- **Kueue:** Use `stable-v1.2` for the Kueue operator channel.
- **OCP requirement:** Minimum OpenShift version is **4.19**.
