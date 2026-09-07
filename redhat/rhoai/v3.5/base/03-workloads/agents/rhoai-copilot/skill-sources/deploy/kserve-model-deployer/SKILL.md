---
name: kserve-model-deployer
description: "Deploy predictive and generative models via KServe InferenceService with proper runtime, resource configuration, and GitOps-compatible manifests."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, KServe, InferenceService, Model Serving, vLLM, OpenVINO, Caikit, Deployment]
---

# KServe Model Deployer

Deploy predictive and generative AI models using KServe `InferenceService` on OpenShift AI. Handles runtime selection (vLLM, OpenVINO, Caikit, custom), deployment mode (RawDeployment vs Serverless/Knative), resource sizing, autoscaling, authentication, and GitOps manifest generation.

## Trigger Conditions

- "Deploy a model for inference"
- "Create an InferenceService for my model"
- "Serve a model with vLLM on OpenShift AI"
- "Deploy an OpenVINO model"
- "Set up model serving with KServe"
- "Configure GPU resources for model serving"
- "Deploy a model with autoscaling"
- "Switch model from Serverless to RawDeployment"
- "Generate model deployment YAML for ArgoCD"
- "Deploy a custom serving runtime"
- "How do I serve a model on RHOAI?"

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| mcp_rhoai | `list_serving_runtimes` | Available serving runtimes on the cluster |
| mcp_rhoai | `list_inference_services` | Existing model deployments |
| mcp_rhoai | `get_inference_service` | Detailed status of a specific deployment |
| mcp_rhoai | `estimate_serving_resources` | Recommended resource sizing for a model |
| mcp_rhoai | `check_deployment_prerequisites` | Verify cluster readiness for deployment |
| mcp_rhoai | `prepare_model_deployment` | Generate deployment manifests |
| mcp_rhoai | `deploy_model` | Apply model deployment |
| mcp_openshift | `nodes_top` | GPU/CPU availability on cluster nodes |
| mcp_openshift | `pods_list` | Check serving pod health |
| mcp_openshift | `events_list` | Diagnose deployment failures |

## Procedure

### Phase 1: Pre-Deployment Validation

1. Call `mcp_rhoai_check_deployment_prerequisites` to verify:
   - KServe component is `Managed` in the DSC
   - Required CRDs are installed (`InferenceService`, `ServingRuntime`)
   - Target namespace exists and has the correct labels
   - Model storage is accessible (S3, PVC, or OCI)

2. Call `mcp_rhoai_list_serving_runtimes` to identify available runtimes:

| Runtime | Models | Framework | GPU Required |
|---------|--------|-----------|-------------|
| vLLM | LLMs (Llama, Mistral, Qwen) | PyTorch/Safetensors | Yes |
| OpenVINO Model Server | Classification, detection, NLP | OpenVINO IR, ONNX | Optional |
| Caikit-TGIS | Text generation | Caikit format | Yes |
| Caikit-NLP | NLP tasks | Caikit format | Optional |
| Custom | Any | User-defined | Varies |

3. Call `mcp_openshift_nodes_top` to verify GPU/CPU capacity for the deployment.

4. Call `mcp_rhoai_estimate_serving_resources` with the model name/size to get recommended resource allocation.

### Phase 2: Determine Deployment Configuration

5. Select the deployment mode:

| Mode | Managed By | Use Case | Scale-to-Zero |
|------|-----------|----------|---------------|
| **RawDeployment** | Kubernetes Deployment | Predictable traffic, always-on models | No |
| **Serverless** (Knative) | Knative Serving | Bursty traffic, cost optimization | Yes |

   Check which mode is configured at the cluster level:
   ```bash
   oc get dsc default-dsc -o jsonpath='{.spec.components.kserve.serving.managementState}'
   # If Managed → Serverless available; if Unmanaged → RawDeployment only
   ```

6. Determine model storage:

| Storage Type | URI Format | When to Use |
|-------------|------------|-------------|
| S3 / MinIO | `s3://{bucket}/{path}` | Standard object storage |
| PVC | `pvc://{pvc-name}/{path}` | Pre-downloaded models on cluster |
| OCI | `oci://{registry}/{repo}:{tag}` | Container registry model artifacts |
| HTTP | `https://{url}` | Public model endpoints |

7. If using S3, ensure a data connection secret exists:
   ```bash
   oc get secret {data-connection-name} -n {namespace} \
     -o jsonpath='{.data.AWS_S3_ENDPOINT}' | base64 -d
   ```

### Phase 3: Create the InferenceService

8. Generate the InferenceService manifest based on gathered parameters.

**vLLM LLM Deployment (GPU, RawDeployment):**

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: {model-name}
  namespace: {namespace}
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
    serving.knative.openshift.io/enablePassthrough: "true"
  labels:
    opendatahub.io/dashboard: "true"
spec:
  predictor:
    model:
      modelFormat:
        name: vLLM
      runtime: vllm-runtime
      storageUri: "s3://{bucket}/{model-path}"
      args:
        - "--max-model-len=4096"
        - "--dtype=auto"
        - "--enable-auto-tool-choice"
      resources:
        requests:
          cpu: "4"
          memory: 16Gi
          nvidia.com/gpu: "1"
        limits:
          cpu: "8"
          memory: 32Gi
          nvidia.com/gpu: "1"
    minReplicas: 1
    maxReplicas: 3
```

**OpenVINO Predictive Model (CPU, Serverless):**

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: {model-name}
  namespace: {namespace}
  labels:
    opendatahub.io/dashboard: "true"
spec:
  predictor:
    model:
      modelFormat:
        name: openvino_ir
      runtime: ovms
      storageUri: "s3://{bucket}/{model-path}"
      resources:
        requests:
          cpu: "2"
          memory: 4Gi
        limits:
          cpu: "4"
          memory: 8Gi
    minReplicas: 0
    maxReplicas: 5
    scaleTarget: 10
    scaleMetric: concurrency
```

**Caikit Text Generation (GPU, RawDeployment):**

```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: {model-name}
  namespace: {namespace}
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
  labels:
    opendatahub.io/dashboard: "true"
spec:
  predictor:
    model:
      modelFormat:
        name: caikit
      runtime: caikit-tgis-runtime
      storageUri: "s3://{bucket}/{model-path}"
      resources:
        requests:
          cpu: "4"
          memory: 16Gi
          nvidia.com/gpu: "1"
        limits:
          cpu: "8"
          memory: 32Gi
          nvidia.com/gpu: "1"
    minReplicas: 1
    maxReplicas: 1
```

9. Apply the InferenceService:
   ```bash
   oc apply -f inference-service.yaml
   ```

### Phase 4: Wait for Deployment Readiness

10. Monitor the deployment status:
    ```bash
    oc wait inferenceservice {model-name} -n {namespace} \
      --for=condition=Ready --timeout=600s
    ```

11. Check pod status if deployment is slow:
    ```bash
    oc get pods -n {namespace} -l serving.kserve.io/inferenceservice={model-name} --no-headers
    ```

12. Call `mcp_openshift_events_list` for the namespace to catch scheduling or image pull issues.

13. Common startup delays:
    - Model download from S3 (large models can take 10-30 minutes)
    - GPU scheduling (if no GPUs are immediately available)
    - Image pull (vLLM/OVMS images are several GB)

### Phase 5: Verify and Test

14. Get the inference endpoint:

    **RawDeployment:**
    ```bash
    oc get inferenceservice {model-name} -n {namespace} \
      -o jsonpath='{.status.url}'
    ```

    **Serverless (Knative):**
    ```bash
    oc get ksvc {model-name}-predictor -n {namespace} \
      -o jsonpath='{.status.url}'
    ```

15. Test the endpoint:

    **vLLM (OpenAI-compatible):**
    ```bash
    ENDPOINT=$(oc get inferenceservice {model-name} -n {namespace} -o jsonpath='{.status.url}')
    TOKEN=$(oc whoami -t)

    curl -s "$ENDPOINT/v1/chat/completions" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d '{
        "model": "{model-name}",
        "messages": [{"role":"user","content":"Hello"}],
        "max_tokens": 50
      }'
    ```

    **OpenVINO (v2 inference protocol):**
    ```bash
    curl -s "$ENDPOINT/v2/models/{model-name}/infer" \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"inputs":[{"name":"input","shape":[1,3,224,224],"datatype":"FP32","data":[...]}]}'
    ```

### Phase 6: Configure Authentication

16. Check if auth is enabled at the cluster level:
    ```bash
    oc get dsc default-dsc -o jsonpath='{.spec.components.kserve.serving.ingressGateway}'
    ```

17. For OpenShift auth integration (default in RHOAI), the Route requires a Bearer token from `oc whoami -t`. No additional configuration is needed.

18. For public endpoints (not recommended in production):
    ```bash
    oc annotate inferenceservice {model-name} -n {namespace} \
      security.opendatahub.io/enable-auth="false"
    ```

### Phase 7: Generate GitOps Manifests

19. Output the complete deployment as GitOps-compatible YAML:
    - InferenceService CR (stripped of server-side fields)
    - ServingRuntime CR (if custom)
    - S3 data connection Secret (with placeholder credentials)
    - HardwareProfile reference (if applicable)
    - NetworkPolicy (if namespace isolation is required)
    - Place under the appropriate Kustomize overlay directory

## Output Format

```
# Model Deployment Report — {timestamp}

## Pre-Deployment Checks
| Check | Status |
|-------|--------|
| KServe component Managed | ✓/✗ |
| Target namespace exists | ✓/✗ |
| Runtime available | ✓/✗ ({runtime}) |
| Model storage accessible | ✓/✗ |
| GPU capacity available | ✓/✗ ({available}/{requested}) |

## Deployment Configuration
- Model: {model-name}
- Namespace: {namespace}
- Runtime: {runtime}
- Deployment Mode: {RawDeployment/Serverless}
- Storage URI: {uri}
- Replicas: {min}-{max}

## Resources
| Resource | Request | Limit |
|----------|---------|-------|
| CPU | {req} | {limit} |
| Memory | {req} | {limit} |
| GPU | {req} | {limit} |

## Deployment Status
- InferenceService: {Ready/Progressing/Failed}
- Pods: {running}/{desired}
- Endpoint: {url}

## Test Result
- Protocol: {OpenAI/v2/gRPC}
- Response: {success/failure}
- Latency: {ms}

## GitOps Manifests
{YAML for ArgoCD deployment}
```

## Safety Constraints

- Never deploy a model with GPU requests exceeding the cluster's available GPU capacity — verify with `mcp_openshift_nodes_top` before applying
- Always set memory limits at least 2x the model size to account for KV cache and runtime overhead — undersized limits cause OOMKills during inference
- Do not set `minReplicas: 0` with `RawDeployment` mode — scale-to-zero only works with Serverless/Knative; setting 0 replicas in RawDeployment removes all serving pods
- Never disable authentication on production InferenceServices — the default OpenShift auth integration provides token-based access control
- Verify the model format matches the selected runtime — a vLLM runtime cannot serve OpenVINO IR models and vice versa
- Do not set `maxReplicas` higher than the number of nodes that can support the resource requirements — autoscaler cannot create nodes with GPUs if none exist in the pool
- Large model downloads can take 30+ minutes — set appropriate `timeoutSeconds` on the InferenceService to avoid premature pod termination
- All deployment changes must go through Git (PR) — never apply InferenceService manifests directly with `oc apply` in production

## Disconnected Environment Notes

- Serving runtime container images (vLLM, OpenVINO, Caikit) must be mirrored to the internal registry; update the ServingRuntime CR's container image reference
- Model artifacts must be stored in a cluster-accessible location: internal S3 (MinIO), PVC, or internal OCI registry — external model hubs (HuggingFace) are unreachable
- OCI-based model storage (`oci://`) works well in disconnected environments — mirror the model OCI artifact to the internal registry using `oc image mirror` or `skopeo`
- The KServe storage initializer container pulls models at pod startup — ensure its image is mirrored and the `storageUri` points to an internal endpoint
- If using S3 (MinIO), the data connection secret must include the internal MinIO endpoint and TLS CA if using self-signed certificates
- Knative Serving (Serverless mode) requires the Knative images to be mirrored — use RawDeployment mode if Knative mirroring is incomplete
- Ensure the OpenShift ingress controller's wildcard certificate is trusted by clients — model endpoints are exposed via OpenShift Routes

## Related Skills

- `llmd-deployment-manager` — deploy with llm-d for distributed multi-node inference
- `maas-deploy-model` — deploy a model and expose via the MaaS governance layer
- `maas-enable` — enable MaaS on a fresh cluster
