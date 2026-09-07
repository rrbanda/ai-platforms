---
name: llmd-deployment-manager
description: "Deploy and configure LLMInferenceService for distributed inference with llm-d on Red Hat OpenShift AI 3.5."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Deploy, llm-d, LLMInferenceService, Distributed-Inference, KServe, Gateway, EPP]
---

# llm-d Deployment Manager

Deploy and configure LLMInferenceService resources for distributed LLM inference using llm-d on Red Hat OpenShift AI 3.5. Manages the full deployment stack: model server pods, Endpoint Picker (EPP) for intelligent routing, Gateway HTTPRoute for traffic ingress, and optional multi-node parallelism via LeaderWorkerSet.

## Trigger Conditions

- "Deploy a model with llm-d"
- "Create an LLMInferenceService"
- "Set up distributed inference on OpenShift AI"
- "Configure multi-GPU inference with tensor parallelism"
- "Deploy a large model across multiple nodes"
- "Set up prefix cache scoring for my model"
- "Configure llm-d with EPP routing"
- "How do I serve a 70B model on RHOAI?"
- User needs to deploy an LLM that requires more than 8 accelerators (multi-node)
- User wants intelligent request routing with KV-cache affinity

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| mcp_rhoai | `list_inference_services` | Discover existing deployments and their configurations |
| mcp_rhoai | `get_inference_service` | Retrieve detailed status and spec of a deployment |
| mcp_rhoai | `estimate_serving_resources` | Calculate GPU/memory requirements for a model |
| mcp_rhoai | `check_deployment_prerequisites` | Verify Gateway, GatewayClass, and operator readiness |
| mcp_rhoai | `get_cluster_resources` | Check available GPU capacity across nodes |
| mcp_openshift | `nodes_top` | Real-time node utilization (GPU, CPU, memory) |
| mcp_openshift | `pods_list` | List model server and EPP pods, check readiness |
| mcp_openshift | `events_list` | Surface scheduling failures, image pull issues, or readiness probe failures |
| mcp_argocd | `get_application` | Check GitOps sync status for managed deployments |

## Procedure

### Phase 1: Validate Prerequisites

1. Verify OpenShift version (4.19.9+ required):
   ```bash
   oc get clusterversion -o jsonpath='{.items[0].status.desired.version}'
   ```

2. Check Gateway infrastructure is in place:
   ```bash
   oc get gatewayclass
   # Must have a GatewayClass for inference

   oc get gateway openshift-ai-inference -n openshift-ingress
   # Must exist and be Accepted
   ```

3. Call `mcp_rhoai.check_deployment_prerequisites` to validate all dependencies.

4. Verify the serving.kserve.io CRD exists:
   ```bash
   oc get crd llminferenceservices.serving.kserve.io
   ```

5. If multi-node deployment is needed (parallelism > 8 accelerators), verify LeaderWorkerSet Operator:
   ```bash
   oc get csv -n openshift-operators | grep leaderworkerset
   # Must show Succeeded
   ```

### Phase 2: Assess Resource Requirements

6. Call `mcp_rhoai.estimate_serving_resources` with the model ID and desired parallelism.

7. Call `mcp_rhoai.get_cluster_resources` to verify sufficient GPU capacity:
   - Identify nodes with the required accelerator type
   - Confirm enough free accelerators for the parallelism configuration

8. Call `mcp_openshift.nodes_top` to check real-time utilization.

9. Determine parallelism configuration:

   | Model Size | Accelerator | Recommended Parallelism |
   |------------|-------------|------------------------|
   | ≤8B | 1× A100-80GB / 1× H100 | tensor: 1 |
   | 8B–13B | 1–2× A100-80GB | tensor: 1–2 |
   | 13B–34B | 2–4× A100-80GB | tensor: 2–4 |
   | 34B–70B | 4–8× A100-80GB | tensor: 4–8 |
   | 70B+ | 8+× (multi-node) | tensor: 8, data: 2+ |

### Phase 3: Determine Model Source

10. Identify the model URI format:

    | Source | URI Format | Example |
    |--------|-----------|---------|
    | HuggingFace | `hf://<org>/<model>` | `hf://meta-llama/Llama-3.1-70B-Instruct` |
    | PVC | `pvc://<pvc-name>/<path>` | `pvc://model-store/llama-70b/` |
    | OCI Registry | `oci://<registry>/<repo>:<tag>` | `oci://registry.example.com/models/llama:v1` |
    | S3 | `s3://<bucket>/<key>` | `s3://models/llama-70b/` |

11. For S3 sources, ensure a data connection Secret exists:
    ```bash
    oc get secret <s3-secret> -n <namespace>
    ```

### Phase 4: Generate LLMInferenceService Manifest

12. Generate the base LLMInferenceService:
    ```yaml
    apiVersion: serving.kserve.io/v1alpha1
    kind: LLMInferenceService
    metadata:
      name: <deployment-name>
      namespace: <namespace>
    spec:
      modelUri: "<model-uri>"
      parallelism:
        tensor: <tp-degree>
      accelerator:
        count: <total-gpus>
    ```

13. For multi-node deployments with data parallelism:
    ```yaml
    apiVersion: serving.kserve.io/v1alpha1
    kind: LLMInferenceService
    metadata:
      name: <deployment-name>
      namespace: <namespace>
    spec:
      modelUri: "hf://<org>/<model>"
      parallelism:
        tensor: 8
        data: 2
      accelerator:
        count: 16
    ```

14. For local data parallelism (multiple model replicas on same node):
    ```yaml
    spec:
      parallelism:
        tensor: 4
        dataLocal: 2
      accelerator:
        count: 8
    ```

15. Configure scheduler plugins for intelligent routing (optional — omit for operator defaults):
    ```yaml
    spec:
      scheduler:
        plugins:
          scorers:
            - name: prefix-cache-scorer
              weight: 80
            - name: queue-scorer
              weight: 20
    ```

    | Plugin | Purpose | Best For |
    |--------|---------|----------|
    | `prefix-cache-scorer` | Routes to pods with cached KV-cache prefixes | Chat, long-context, RAG |
    | `queue-scorer` | Routes to least-loaded pod | Uniform short requests |

16. Configure custom route/gateway (optional — omit for operator-managed defaults):
    ```yaml
    spec:
      route:
        gatewayRef:
          name: openshift-ai-inference
          namespace: openshift-ingress
    ```

    Leaving `route`, `gateway`, and `scheduler` empty means the operator provisions and manages them automatically.

### Phase 5: Deploy

17. Apply the LLMInferenceService:
    ```bash
    oc apply -f <deployment-manifest>.yaml
    ```

18. Monitor deployment rollout:
    ```bash
    oc get llminferenceservice <name> -n <namespace> -w
    ```

19. Check component readiness:
    ```bash
    # Model server pods
    oc get pods -l serving.kserve.io/llminferenceservice=<name> -n <namespace>

    # EPP pod
    oc get pods -l app=epp,serving.kserve.io/llminferenceservice=<name> -n <namespace>

    # HTTPRoute
    oc get httproute -l serving.kserve.io/llminferenceservice=<name> -n <namespace>
    ```

20. Wait for Ready condition:
    ```bash
    oc wait llminferenceservice <name> -n <namespace> \
      --for=condition=Ready --timeout=600s
    ```

### Phase 6: Verify and Test

21. Get the inference endpoint:
    ```bash
    oc get llminferenceservice <name> -n <namespace> \
      -o jsonpath='{.status.url}'
    ```

22. Test with a completion request:
    ```bash
    ENDPOINT=$(oc get llminferenceservice <name> -n <namespace> -o jsonpath='{.status.url}')
    curl -s "$ENDPOINT/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -d '{
        "model": "<model-name>",
        "messages": [{"role": "user", "content": "Hello, how are you?"}],
        "max_tokens": 100
      }'
    ```

23. Verify EPP routing is active:
    ```bash
    oc logs -l app=epp,serving.kserve.io/llminferenceservice=<name> -n <namespace> --tail=20
    # Should show routing decisions with scorer weights
    ```

24. Call `mcp_openshift.pods_list` and `mcp_openshift.events_list` to confirm no errors.

## Output Format

```
# llm-d Deployment: {deployment_name}

## Status
- LLMInferenceService: {Ready|Progressing|Failed}
- Model server pods: {ready}/{total}
- EPP: {Running|Pending}
- HTTPRoute: {Accepted|Pending}

## Configuration
- Model: {model_uri}
- Parallelism: tensor={tp}, data={dp}, dataLocal={dl}
- Total accelerators: {count}× {type}
- Nodes used: {node_count}
- Scheduler: {plugins or "operator-managed"}

## Endpoint
- URL: {endpoint_url}
- Gateway: {gateway_name} ({namespace})

## Routing
| Plugin | Weight | Purpose |
|--------|--------|---------|
| {name} | {weight} | {description} |

## Resource Allocation
| Component | CPU | Memory | GPU |
|-----------|-----|--------|-----|
| Model server (×{n}) | {cpu} | {mem} | {gpu} |
| EPP | {cpu} | {mem} | — |

## Test Result
- Endpoint reachable: {yes/no}
- First token latency: {ms}ms
- Model responding: {yes/no}
```

## Safety Constraints

- Never deploy without first confirming sufficient GPU capacity — failed scheduling wastes queue time and blocks other workloads
- Do not modify the `openshift-ai-inference` Gateway without explicit approval — it affects all inference workloads
- Verify OCP version is 4.19.9+ before creating LLMInferenceService — older versions lack required Gateway API support
- Never hardcode model access tokens in the manifest; use Kubernetes Secrets or ServiceAccount-based auth
- Warn the user before deploying multi-node (LeaderWorkerSet) — it requires the LeaderWorkerSet Operator and consumes significant cluster resources
- Do not set `parallelism.tensor` higher than the model architecture supports (check model's `num_attention_heads` must be divisible by TP degree)
- If the deployment fails, do not repeatedly re-apply — diagnose root cause first via events and pod logs
- Always validate that the model URI is accessible from the cluster before deploying (image pull or storage connectivity)

## Disconnected Environment Notes

- HuggingFace URI (`hf://`) will fail without external network; use `pvc://` or `oci://` with pre-cached models instead
- Mirror model server images from `quay.io` and `registry.redhat.io` to the internal registry
- For OCI model URIs, the internal OCI registry must be configured as a mirror source in the cluster's ImageDigestMirrorSet
- S3 sources work if pointing to in-cluster MinIO/Ceph — ensure the endpoint URL in the data connection Secret uses the internal service address
- EPP and Gateway components are deployed from operator-managed images — ensure operator catalogs are mirrored
- Scheduler plugin configurations are cluster-internal and do not require external connectivity
- If the model was downloaded from HuggingFace, ensure tokenizer files are included alongside model weights on the PVC/OCI artifact (vLLM requires `tokenizer_config.json`)

## Related Skills

- `kserve-model-deployer` — deploy standard KServe InferenceService (single-node, non-distributed)
- `maas-deploy-model` — deploy a model and expose via the MaaS governance layer
- `maas-enable` — enable MaaS on a fresh cluster
