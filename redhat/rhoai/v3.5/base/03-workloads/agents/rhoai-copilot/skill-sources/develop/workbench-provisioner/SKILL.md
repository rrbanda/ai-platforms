---
name: workbench-provisioner
description: "Create and configure workbenches (Jupyter notebooks) with proper IDE images, GPU resources, storage, and data connections."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Workbench, Notebook, JupyterLab, VS Code, RStudio, GPU, Storage]
---

# Workbench Provisioner

Create and configure data science workbenches on OpenShift AI. Handles IDE image selection, notebook image configuration, GPU/CPU resource sizing via hardware profiles, persistent storage provisioning, S3 data connections, and custom image registration.

## Trigger Conditions

- "Create a new workbench"
- "Set up a Jupyter notebook on RHOAI"
- "Provision a workbench with GPU"
- "Create a VS Code workbench"
- "Set up an RStudio workbench"
- "Add storage to my workbench"
- "Connect S3 data to my workbench"
- "What notebook images are available?"
- "Create a workbench with a custom image"
- "Set up a workbench for LLM development"
- "Provision workbenches for my team"

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| mcp_rhoai | `create_workbench` | Create a new workbench |
| mcp_rhoai | `list_workbenches` | List existing workbenches |
| mcp_rhoai | `get_workbench` | Get workbench details and status |
| mcp_rhoai | `list_notebook_images` | Available notebook images |
| mcp_rhoai | `create_s3_data_connection` | Attach S3 storage to a workbench |
| mcp_rhoai | `list_data_connections` | Existing data connections in namespace |
| mcp_rhoai | `list_storage` | PVCs available in the namespace |
| mcp_openshift | `resources_list` | List Notebooks, PVCs, Secrets, HardwareProfiles |
| mcp_openshift | `pods_list` | Check workbench pod health |
| mcp_openshift | `events_list` | Diagnose startup failures |

## Procedure

### Phase 1: Gather Requirements

1. Determine the workbench configuration from user requirements:

| Parameter | Options | Default |
|-----------|---------|---------|
| **IDE** | JupyterLab, VS Code (code-server), RStudio | JupyterLab |
| **Notebook Image** | Standard Data Science, CUDA, PyTorch, TensorFlow, HabanaAI, Minimal | Standard Data Science |
| **Resources** | CPU-only, single GPU, multi-GPU | CPU-only |
| **Storage** | PVC size for workspace persistence | 20Gi |
| **Data Connections** | S3, database connections | None |
| **Custom Image** | User-provided container image | None |

2. Call `mcp_rhoai_list_notebook_images` to get available images:

| Image Category | GPU Support | Typical Use Case |
|---------------|-------------|-----------------|
| Standard Data Science | No | General ML, scikit-learn, pandas |
| CUDA - Standard Data Science | Yes | GPU-accelerated ML workflows |
| PyTorch | Yes | PyTorch model development |
| TensorFlow | Yes | TensorFlow model development |
| Minimal Python | No | Lightweight scripting |
| HabanaAI | Gaudi only | Intel Gaudi accelerated training |
| code-server (VS Code) | Varies | VS Code IDE in browser |
| RStudio | No | R-based data science |

3. Verify the target namespace exists:
   ```bash
   oc get project {namespace}
   ```

### Phase 2: Configure Resources

4. Call `mcp_openshift_resources_list` with kind=`HardwareProfile` in `redhat-ods-applications` to find suitable profiles:
   ```bash
   oc get hardwareprofiles -n redhat-ods-applications -o custom-columns=\
   'NAME:.metadata.name,DISPLAY:.spec.displayName,GPU:.spec.identifiers[?(@.identifier=="nvidia.com/gpu")].defaultCount,ENABLED:.spec.enabled'
   ```

5. If no suitable hardware profile exists, recommend creating one (see `hardware-profile-manager` skill).

6. For GPU workbenches, verify GPU availability:
   - Call `mcp_openshift_nodes_top` to check GPU allocation
   - Ensure at least one node has the required GPU type available

7. Check namespace quotas:
   ```bash
   oc get resourcequota -n {namespace} -o yaml
   ```
   Verify the workbench resource requests fit within remaining quota.

### Phase 3: Set Up Storage

8. Create a PVC for workbench persistence (if not using an existing one):

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {workbench-name}-pvc
  namespace: {namespace}
  labels:
    opendatahub.io/dashboard: "true"
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: {size}
  storageClassName: {storage-class}
```

9. Apply the PVC:
   ```bash
   oc apply -f workbench-pvc.yaml
   ```

10. Call `mcp_rhoai_list_storage` to verify available PVCs in the namespace.

### Phase 4: Configure Data Connections

11. If S3 data connections are needed, call `mcp_rhoai_list_data_connections` to check for existing ones.

12. Create a new S3 data connection:
    - Call `mcp_rhoai_create_s3_data_connection` with:
      - `name`: descriptive connection name
      - `namespace`: target namespace
      - `access_key`: S3 access key
      - `secret_key`: S3 secret key
      - `endpoint`: S3 endpoint URL
      - `bucket`: default bucket name
      - `region`: S3 region (if applicable)

    Or create manually:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: {connection-name}
  namespace: {namespace}
  labels:
    opendatahub.io/dashboard: "true"
    opendatahub.io/managed: "true"
  annotations:
    opendatahub.io/connection-type: s3
    openshift.io/display-name: "{display-name}"
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "{access-key}"
  AWS_SECRET_ACCESS_KEY: "{secret-key}"
  AWS_S3_ENDPOINT: "{endpoint}"
  AWS_S3_BUCKET: "{bucket}"
  AWS_DEFAULT_REGION: "{region}"
```

13. Apply the secret:
    ```bash
    oc apply -f data-connection.yaml
    ```

### Phase 5: Create the Workbench

14. Call `mcp_rhoai_create_workbench` with the gathered parameters, or generate the Notebook CR directly.

**JupyterLab Workbench with GPU:**

```yaml
apiVersion: kubeflow.org/v1
kind: Notebook
metadata:
  name: {workbench-name}
  namespace: {namespace}
  labels:
    app: {workbench-name}
    opendatahub.io/dashboard: "true"
    opendatahub.io/odh-managed: "true"
  annotations:
    notebooks.opendatahub.io/inject-oauth: "true"
    notebooks.opendatahub.io/notebook-image: "{image-name}"
    notebooks.opendatahub.io/notebook-image-order: "0"
    opendatahub.io/hardware-profile: "{hardware-profile-name}"
    opendatahub.io/username: "{username}"
spec:
  template:
    spec:
      containers:
        - name: {workbench-name}
          image: "{full-image-reference}"
          resources:
            requests:
              cpu: "2"
              memory: 8Gi
              nvidia.com/gpu: "1"
            limits:
              cpu: "4"
              memory: 16Gi
              nvidia.com/gpu: "1"
          env:
            - name: NOTEBOOK_ARGS
              value: |-
                --ServerApp.port=8888
                --ServerApp.token=''
                --ServerApp.password=''
                --ServerApp.base_url=/notebook/{namespace}/{workbench-name}
                --ServerApp.quit_button=False
          volumeMounts:
            - name: workspace
              mountPath: /opt/app-root/src
          ports:
            - containerPort: 8888
              name: notebook-port
              protocol: TCP
      volumes:
        - name: workspace
          persistentVolumeClaim:
            claimName: {workbench-name}-pvc
      tolerations:
        - key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
```

**CPU-Only VS Code Workbench:**

```yaml
apiVersion: kubeflow.org/v1
kind: Notebook
metadata:
  name: {workbench-name}
  namespace: {namespace}
  labels:
    app: {workbench-name}
    opendatahub.io/dashboard: "true"
    opendatahub.io/odh-managed: "true"
  annotations:
    notebooks.opendatahub.io/inject-oauth: "true"
    notebooks.opendatahub.io/notebook-image: "code-server"
    opendatahub.io/hardware-profile: "cpu-small"
    opendatahub.io/username: "{username}"
spec:
  template:
    spec:
      containers:
        - name: {workbench-name}
          image: "{code-server-image-reference}"
          resources:
            requests:
              cpu: "1"
              memory: 4Gi
            limits:
              cpu: "2"
              memory: 8Gi
          volumeMounts:
            - name: workspace
              mountPath: /opt/app-root/src
          ports:
            - containerPort: 8888
              name: notebook-port
              protocol: TCP
      volumes:
        - name: workspace
          persistentVolumeClaim:
            claimName: {workbench-name}-pvc
```

15. To attach data connections to the workbench, add environment variables from the connection secret:

```yaml
envFrom:
  - secretRef:
      name: {data-connection-name}
```

16. Apply the workbench:
    ```bash
    oc apply -f workbench.yaml
    ```

### Phase 6: Wait for Startup and Validate

17. Wait for the workbench pod to become ready:
    ```bash
    oc wait notebook {workbench-name} -n {namespace} --for=condition=Ready --timeout=600s
    ```

18. Call `mcp_rhoai_get_workbench` to verify the workbench status.

19. If the workbench is not starting, call `mcp_openshift_events_list` for the namespace:
    - Check for `FailedScheduling` (resource constraints)
    - Check for `ImagePullBackOff` (image not available)
    - Check for `FailedAttachVolume` (PVC issues)

20. Verify the workbench URL is accessible:
    ```bash
    oc get route {workbench-name} -n {namespace} -o jsonpath='{.spec.host}'
    ```

### Phase 7: Register Custom Images (Optional)

21. If the user needs a custom notebook image, register it:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {image-name}-notebook-image
  namespace: redhat-ods-applications
  labels:
    app.kubernetes.io/part-of: opendatahub
    opendatahub.io/notebook-image: "true"
data:
  displayName: "{display-name}"
  description: "{description}"
  imageUrl: "{registry}/{repository}:{tag}"
  tags: '["python3.11","cuda12.4","custom"]'
  order: "100"
  recommended: "false"
```

22. Apply the custom image registration:
    ```bash
    oc apply -f custom-notebook-image.yaml
    ```

23. Verify the image appears in the dashboard:
    ```bash
    oc get configmaps -n redhat-ods-applications -l opendatahub.io/notebook-image=true
    ```

### Phase 8: Generate GitOps Manifests

24. Output all workbench resources as GitOps-compatible YAML:
    - Notebook CR
    - PersistentVolumeClaim
    - Data connection Secrets (with placeholder credentials)
    - Custom image ConfigMaps (if applicable)
    - Place under the appropriate Kustomize overlay directory

## Output Format

```
# Workbench Provisioning Report — {timestamp}

## Available Notebook Images
| Image | Version | GPU Support | Status |
|-------|---------|-------------|--------|
| {name} | {version} | ✓/✗ | Available |

## Workbench Configuration
- Name: {workbench-name}
- Namespace: {namespace}
- IDE: {JupyterLab/VS Code/RStudio}
- Image: {image-name}
- Hardware Profile: {profile-name}

## Resources
| Resource | Request | Limit |
|----------|---------|-------|
| CPU | {req} | {limit} |
| Memory | {req} | {limit} |
| GPU | {req} | {limit} |

## Storage
| PVC | Size | StorageClass | Status |
|-----|------|-------------|--------|
| {name} | {size} | {class} | Bound |

## Data Connections
| Name | Type | Endpoint | Bucket |
|------|------|----------|--------|
| {name} | S3 | {endpoint} | {bucket} |

## Workbench Status
- Pod: {Running/Pending/Failed}
- URL: https://{route-host}
- Ready: ✓/✗

## GitOps Manifests
{YAML for ArgoCD deployment}
```

## Safety Constraints

- Never create workbenches with GPU resources if no GPU nodes are available — the pod will remain Pending indefinitely, blocking the GPU resource quota
- Do not store S3 credentials or data connection secrets in plain text within the Notebook CR — always use Kubernetes Secrets referenced via `envFrom` or `secretRef`
- Verify the notebook image exists and is pullable before creating the workbench — ImagePullBackOff errors require manual intervention
- CUDA notebook images are 8-15GB — first pulls can timeout with default image pull deadlines; warn the user about expected startup time
- Never set memory requests below 2Gi for any workbench — the Jupyter/VS Code server process itself requires at least 1.5Gi
- Workbenches are StatefulSets — deleting the Notebook CR also deletes the pod but preserves the PVC; explicitly inform the user before PVC deletion as data loss is irreversible
- Idle workbenches consume cluster resources — recommend configuring idle culling at the cluster level for cost optimization
- Custom images must run as non-root and be compatible with OpenShift's `restricted-v2` SCC — images that require root will fail to start
- All workbench changes must go through Git (PR) — never apply Notebook CRs directly with `oc apply` in production

## Disconnected Environment Notes

- All notebook images (JupyterLab, VS Code, RStudio, CUDA variants) must be mirrored to the internal registry; update image references in the Notebook CR and any custom image ConfigMaps
- CUDA images depend on NVIDIA base layers — mirror the full image chain including all base layers
- S3 data connections must point to the internal MinIO or S3-compatible storage — external endpoints are unreachable in air-gapped environments
- Custom image registration ConfigMaps must reference internal registry paths (`{internal-registry}/{repository}:{tag}`)
- The OAuth proxy sidecar container image (`registry.redhat.io/openshift4/ose-oauth-proxy`) must be mirrored — it is injected into every workbench pod via the `inject-oauth` annotation
- PVC StorageClasses must be available in the disconnected cluster — verify the default StorageClass is configured and provisioner is operational
- Pip/conda package installations inside workbenches need an internal PyPI mirror or pre-built images with required packages
