---
name: serving-runtime-advisor
description: "Recommends optimal serving runtime based on model type, size, hardware, and latency requirements."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, MLOps, Serving Runtime, KServe, vLLM, Model Serving]
---

# Serving Runtime Advisor

Recommends the optimal serving runtime for a given model based on type, size, available hardware, and performance requirements.

## Trigger Phrases

- "Which runtime for Llama 70B?"
- "What serving runtime should I use?"
- "Compare vLLM vs TGI for my model"
- "Best runtime for a 7B parameter model"
- "How to serve a fine-tuned model?"

## Procedure

### Phase 1: Gather Model Requirements

1. Ask/identify model characteristics:
   - Model architecture (transformer, diffusion, embedding, etc.)
   - Parameter count (7B, 13B, 70B, etc.)
   - Model format (SafeTensors, GGUF, ONNX, PyTorch)
   - Quantization (none, GPTQ, AWQ, GGML, FP8)
   - Use case (chat, completion, embedding, classification)

### Phase 2: Check Available Runtimes

2. Call `mcp_rhoai_list_serving_runtimes` to get cluster-available runtimes:
   - Note which runtimes are deployed and their versions
   - Check supported model formats for each
3. Call `mcp_openshift_nodes_top` to assess available hardware:
   - GPU types available (A100, H100, T4, L40S)
   - Available GPU memory
   - CPU/RAM capacity

### Phase 3: Runtime Recommendation

4. Apply the decision matrix:

| Model Type | Size | Recommended Runtime | Reason |
|-----------|------|-------------------|--------|
| LLM (decoder) | ≤13B | vLLM | Best throughput, PagedAttention |
| LLM (decoder) | 34-70B | vLLM with tensor parallelism | Multi-GPU support |
| LLM (decoder) | >70B | vLLM + multi-node | Distributed inference |
| Embedding | Any | TEI (Text Embeddings Inference) | Optimized for embeddings |
| Chat + Tools | Any | vLLM with --enable-auto-tool-choice | Function calling support |
| ONNX models | Any | OpenVINO Model Server | CPU-optimized inference |
| Multi-model | Mixed | ModelMesh | Efficient model multiplexing |
| Fine-tuned LoRA | Any | vLLM with --enable-lora | LoRA adapter hot-loading |

5. Estimate resource requirements:

| Model Size | GPU Memory (FP16) | GPU Memory (INT8) | GPU Memory (INT4) |
|-----------|-------------------|-------------------|-------------------|
| 7B | 14 GB | 7 GB | 4 GB |
| 13B | 26 GB | 13 GB | 7 GB |
| 34B | 68 GB | 34 GB | 17 GB |
| 70B | 140 GB | 70 GB | 35 GB |

### Phase 4: Generate Configuration

6. Generate the InferenceService configuration:

**vLLM example:**
```yaml
apiVersion: serving.kserve.io/v1beta1
kind: InferenceService
metadata:
  name: {model-name}
  annotations:
    serving.kserve.io/deploymentMode: RawDeployment
spec:
  predictor:
    model:
      modelFormat:
        name: vLLM
      runtime: vllm-runtime
      storageUri: {storage-path}
      resources:
        limits:
          nvidia.com/gpu: {gpu-count}
        requests:
          memory: {memory}
          cpu: {cpu}
    args:
      - "--max-model-len={context_length}"
      - "--tensor-parallel-size={tp_size}"
```

7. Call `mcp_rhoai_estimate_serving_resources` to validate resource estimates

## Output Format

```
# Serving Runtime Recommendation

## Model Profile
- Name: {model_name}
- Parameters: {size}B
- Architecture: {arch}
- Format: {format}
- Quantization: {quant}
- Use case: {use_case}

## Recommendation: {runtime_name}

**Why**: {reasoning}

### Alternatives Considered
| Runtime | Pros | Cons | Verdict |
|---------|------|------|---------|
| vLLM | {pros} | {cons} | ✓ Selected / ✗ Not ideal |
| TGI | {pros} | {cons} | ✓ Selected / ✗ Not ideal |
| OpenVINO | {pros} | {cons} | ✓ Selected / ✗ Not ideal |

## Resource Requirements
- GPUs: {count}x {type} ({memory} per GPU)
- Total GPU memory: {total}
- System RAM: {ram}
- CPU: {cores} cores
- Storage: {disk} for model weights

## Generated Configuration
```yaml
{InferenceService YAML}
```

## Performance Expectations
- Throughput: ~{tokens}/s (batch={batch_size})
- Latency (p50): ~{latency}ms
- Latency (p99): ~{latency}ms
- Max concurrent requests: ~{concurrent}

## Cluster Fit
- Available GPUs: {available}/{required}
- Memory headroom: {available_mem}/{required_mem}
- Recommendation: {fits/needs_scaling/not_possible}
```

## Domain Knowledge

- vLLM is the default recommended runtime for LLMs in RHOAI 2.16+
- TGI (Text Generation Inference) is being deprecated in favor of vLLM
- ModelMesh is for multi-model serving (many small models on shared GPUs)
- KServe single-model serving is for dedicated GPU allocation per model
- Tensor parallelism requires NVLink or high-bandwidth GPU interconnect
- RHOAI accelerator profiles map to Kubernetes resource requests (nvidia.com/gpu)
- Custom runtimes can be added via ServingRuntime CR in the namespace
- vLLM supports LoRA adapters without full model reload — good for A/B testing
