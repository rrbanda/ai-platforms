---
name: model-catalog-advisor
description: "Discover, compare, and select models from the RHOAI Model Catalog — match models to task requirements, hardware constraints, and performance targets."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Models, Catalog, Planning, LLM, vLLM, GPU]
---

# Model Catalog Advisor

Help users discover, compare, and select models from the RHOAI Model Catalog based on task type, hardware availability, license requirements, and performance targets.

## Trigger Conditions

- "Which model should I use for code generation?"
- "What models are available in the catalog?"
- "Compare granite and llama for summarization"
- "Which models fit on a single A100?"
- "Find models with Apache license"
- "What's the fastest model for tool calling?"
- "Recommend a model for my use case"
- "Show me models that work in disconnected environments"

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| mcp_rhoai | list_registered_models | List models in the catalog |
| mcp_rhoai | get_registered_model | Get model details and metadata |
| mcp_rhoai | list_model_versions | Get available versions/sizes |
| mcp_rhoai | get_model_artifacts | Get model artifacts and storage locations |
| mcp_rhoai | list_serving_runtimes | Get compatible serving runtimes |
| mcp_rhoai | estimate_serving_resources | Estimate GPU/memory needs |
| mcp_rhoai | get_cluster_resources | Check available hardware |
| mcp_openshift | nodes_top | Current node resource usage |

## Procedure

### Phase 1: Understand Requirements

1. Clarify the user's selection criteria:
   - **Task type**: text-generation, code-generation, summarization, classification, embedding, tool-calling, vision, predictive
   - **Hardware constraints**: GPU type and count available, maximum vRAM budget
   - **License requirements**: Apache-2.0, MIT, community license, proprietary acceptable
   - **Performance targets**: latency SLA, throughput (tokens/sec), cold-start tolerance
   - **Environment**: connected or disconnected (air-gapped)

### Phase 2: Catalog Discovery

2. Call `mcp_rhoai` → `list_registered_models` to enumerate the catalog:
   - Note model names, providers, and descriptions
   - Filter by task type if the user specified one
3. For each candidate model, call `mcp_rhoai` → `get_registered_model` to retrieve:
   - Supported tasks and capabilities
   - Model family and parameter count
   - License type
   - Provider (Red Hat, IBM, Meta, Mistral, etc.)
   - Catalog source (default Red Hat catalog or admin-managed ModelCatalogSource CR)
4. Call `mcp_rhoai` → `list_model_versions` for each candidate to get:
   - Available quantizations (FP16, INT8, INT4, GPTQ, AWQ)
   - Model size variants (7B, 13B, 34B, 70B)
   - Validated serving runtime compatibility

### Phase 3: Hardware Feasibility

5. Call `mcp_rhoai` → `get_cluster_resources` to determine available hardware:
   - GPU types and counts (NVIDIA A100, H100, L40S, T4; AMD MI300X)
   - Available vRAM per GPU
   - Current utilization levels
6. Call `mcp_openshift` → `nodes_top` to check real-time resource availability
7. Call `mcp_rhoai` → `estimate_serving_resources` for each candidate model:
   - Minimum vRAM required
   - Recommended GPU count and type
   - Tensor parallelism configuration
8. Eliminate models that exceed available hardware or budget

### Phase 4: Performance Comparison

9. For remaining candidates, compile performance benchmarks:
   - **Cold-start load time**: time from pod scheduled to first token
   - **Minimum vRAM**: minimum GPU memory to load the model
   - **Throughput**: tokens/sec per hardware configuration
   - **Latency**: time-to-first-token (TTFT) and inter-token latency (ITL)
10. For tool-calling use cases, retrieve validated configurations:
    - Exact `vllm serve` CLI arguments for structured output
    - Chat template and tool-calling format (e.g., `--tool-call-parser hermes`)
    - Supported tool-calling protocols (auto, required, none)

### Phase 5: Serving Runtime Selection

11. Call `mcp_rhoai` → `list_serving_runtimes` to match runtimes to models:
    - **vLLM ServingRuntime**: LLMs, chat models, tool-calling
    - **TGIS ServingRuntime**: Text generation with streaming
    - **OpenVINO Model Server**: Optimized CPU inference for predictive models
    - **Caikit+TGIS**: NLP tasks with Caikit runtime
12. For each model-runtime pair, note:
    - Compatible model formats (safetensors, GGUF, ONNX)
    - GPU operator requirements
    - Autoscaling support (KPA, HPA, concurrency-based)

### Phase 6: Recommendation

13. Rank candidates by fit to user requirements:
    - Primary: meets task and hardware constraints
    - Secondary: best performance within constraints
    - Tertiary: license compatibility, community support, Red Hat validation
14. For the top recommendation, provide:
    - Deployment path: deploy directly from catalog or register to model registry first
    - Exact serving runtime and resource configuration
    - vLLM CLI arguments if applicable
    - Expected performance characteristics

## Output Format

```
# Model Catalog Recommendation — {timestamp}

## Requirements Summary
- Task: {task_type}
- Hardware budget: {gpu_type} × {count} ({vram_total} GB vRAM)
- License: {requirement}
- Performance target: {latency/throughput target}

## Catalog Results
| Model | Provider | Parameters | License | Task Match |
|-------|----------|-----------|---------|------------|
| {name} | {provider} | {size} | {license} | {score} |

## Hardware Feasibility
| Model | Min vRAM | GPUs Required | Fits Cluster | Quantization |
|-------|----------|---------------|--------------|--------------|
| {name} | {gb} GB | {n}× {type} | ✅/❌ | {FP16/INT8/INT4} |

## Performance Comparison
| Model | Cold Start | Throughput | TTFT | ITL |
|-------|-----------|-----------|------|-----|
| {name} | {seconds}s | {tok/s} tok/s | {ms} ms | {ms} ms |

## Recommendation

### Primary: {model_name}
- **Why**: {rationale}
- **Runtime**: {serving_runtime}
- **Resources**: {gpu_count}× {gpu_type}
- **Deploy from**: Catalog → {direct deploy | register first}

### vLLM Configuration (if applicable)
```yaml
args:
  - --model={model_path}
  - --tensor-parallel-size={tp}
  - --max-model-len={ctx_length}
  - --gpu-memory-utilization=0.90
  - --enable-auto-tool-choice
  - --tool-call-parser={parser}
```

### Alternative: {model_name}
- **Why**: {rationale for alternative}
- **Trade-off**: {what you gain/lose vs primary}

## Next Steps
1. {action to deploy or register the model}
2. {post-deployment validation step}
```

## Safety Constraints

- Never recommend models that violate the user's stated license requirements
- Always verify hardware feasibility before recommending — do not suggest models that cannot fit available GPUs
- Do not expose internal model storage URIs or credentials
- Clearly distinguish between Red Hat-validated models and community-contributed models
- Warn users about models with restrictive licenses (e.g., non-commercial use only)
- Do not recommend deploying untested quantizations without noting potential accuracy loss

## Disconnected Environment Notes

- In air-gapped clusters, only models pre-loaded to the internal registry are available
- ModelCatalogSource CRs define which models are accessible — check admin-configured sources
- Model artifacts must be stored in the cluster's local S3-compatible storage or pre-cached PVs
- Container images for serving runtimes must exist in the mirrored registry
- Cold-start times may be longer if models are loaded from PVC rather than object storage
- Recommend pre-caching models to LocalModelNode PVs for faster cold starts in disconnected environments
