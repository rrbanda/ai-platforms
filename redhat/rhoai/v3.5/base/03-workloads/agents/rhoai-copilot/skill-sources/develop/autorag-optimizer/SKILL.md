---
name: autorag-optimizer
description: "Configure and run AutoRAG to find the optimal RAG configuration — compare retrieval strategies, view leaderboard results, and generate notebooks for winning patterns."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, AutoRAG, RAG, Optimization, Retrieval, Leaderboard, Notebook, Technology Preview]
---

# Optimize RAG Configuration with AutoRAG

Configure and run AutoRAG optimization to find the best RAG configuration for a given document corpus and use case. AutoRAG systematically compares retrieval strategies, chunking methods, embedding models, and generation parameters to identify the highest-performing pattern.

> **⚠️ TECHNOLOGY PREVIEW:** AutoRAG is a Technology Preview feature in Red Hat OpenShift AI. Technology Preview features are not supported with Red Hat production service level agreements (SLAs), might not be functionally complete, and are not recommended for production use. Optimization results and generated notebooks may require manual validation before production deployment.

## Trigger Conditions

- "Optimize my RAG pipeline"
- "Find the best RAG configuration"
- "Run AutoRAG optimization"
- "Compare retrieval strategies for my documents"
- "Which chunking strategy works best for my use case?"
- "Show the AutoRAG leaderboard"
- "Generate a notebook for the best RAG pattern"
- "Tune my RAG performance"
- "My RAG answers are low quality — help me improve"

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| `mcp_rhoai` | `cluster_summary` | Verify RHOAI version and AutoRAG availability |
| `mcp_rhoai` | `explore_cluster` | Discover existing AutoRAG runs and configurations |
| `mcp_rhoai` | `list_inference_services` | Identify available models for generation and embedding |
| `mcp_openshift` | `pods_list` | Monitor AutoRAG optimization pod status |
| `mcp_openshift` | `events_list` | Diagnose scheduling and resource issues |

## Procedure

### Phase 1: Prerequisites Verification

1. Call `mcp_rhoai.cluster_summary` to confirm:
   - RHOAI version ≥ 3.4
   - AutoRAG component is available
   - Sufficient cluster resources for optimization runs

2. Call `mcp_rhoai.list_inference_services` to identify:
   - Available generation models (chat/completions endpoints)
   - Available embedding models
   - Confirm endpoints are Ready and accessible

3. Call `mcp_rhoai.explore_cluster` to check for:
   - Existing AutoRAG optimization runs
   - Previously completed leaderboard results
   - Configured vector store backends

### Phase 2: Configure Optimization Run

4. Gather optimization parameters from the user:

   | Parameter | Options | Description |
   |-----------|---------|-------------|
   | Document corpus | File path / PVC / S3 | Source documents for RAG evaluation |
   | Evaluation queries | File / generated | Test queries for scoring patterns |
   | Ground truth | File (optional) | Expected answers for accuracy scoring |
   | Retrieval strategies | `vector`, `keyword`, `hybrid`, `rerank` | Methods to compare |
   | Chunking methods | `fixed`, `semantic`, `recursive`, `sentence` | Document splitting strategies |
   | Embedding models | List of deployed models | Embedding endpoints to compare |
   | Generation model | Single model | LLM for answer generation |
   | Metrics | `faithfulness`, `relevancy`, `precision`, `recall` | Scoring criteria |

5. Create the AutoRAG optimization configuration:
   ```yaml
   apiVersion: autorag.opendatahub.io/v1alpha1
   kind: AutoRAGRun
   metadata:
     name: autorag-<use-case>-<timestamp>
     namespace: <project-namespace>
   spec:
     corpus:
       source:
         type: pvc  # or s3, inline
         pvcName: <corpus-pvc>
         path: /documents
     evaluation:
       queries:
         type: generated  # or file
         count: 50
       groundTruth:
         type: file  # optional
         path: /eval/ground-truth.jsonl
       metrics:
         - faithfulness
         - relevancy
         - context_precision
         - answer_correctness
     searchSpace:
       chunking:
         - type: recursive
           chunkSize: [256, 512, 1024]
           chunkOverlap: [20, 50, 100]
         - type: semantic
           breakpointThreshold: [0.3, 0.5, 0.7]
       retrieval:
         - type: vector
           topK: [3, 5, 10]
         - type: hybrid
           topK: [5, 10]
           alpha: [0.3, 0.5, 0.7]
         - type: rerank
           topK: [5, 10]
           rerankModel: <rerank-endpoint>
       embedding:
         models:
           - name: <embedding-model-1>
             endpoint: <url>
           - name: <embedding-model-2>
             endpoint: <url>
     generation:
       model:
         name: <generation-model>
         endpoint: <url>
       parameters:
         temperature: 0.1
         maxTokens: 1024
     resources:
       requests:
         cpu: "4"
         memory: "8Gi"
   ```

6. Apply the AutoRAG run:
   ```bash
   oc apply -f autorag-run.yaml
   ```

### Phase 3: Monitor Optimization

7. Track optimization progress:
   ```bash
   oc get autoragrun <name> -n <namespace> -o jsonpath='{.status}'
   ```
   Status fields:
   - `phase`: Pending → Initializing → Running → Completed
   - `progress`: percentage complete
   - `currentTrial`: which combination is being evaluated
   - `totalTrials`: total combinations to test

8. Call `mcp_openshift.pods_list` to monitor worker pods:
   - Look for pods with label `autorag.opendatahub.io/run=<run-name>`
   - Multiple pods may run in parallel for different configurations

9. Call `mcp_openshift.events_list` if pods are stuck or failing:
   - Check for resource quota issues
   - Check for inference endpoint connectivity problems

### Phase 4: Review Leaderboard

10. Once status is `Completed`, retrieve the leaderboard:
    ```bash
    oc get autoragrun <name> -n <namespace> \
      -o jsonpath='{.status.leaderboard}' | jq .
    ```

11. The leaderboard ranks configurations by composite score:
    - Each entry includes: chunking method, retrieval strategy, embedding model, scores per metric
    - Top entry is the recommended configuration

12. Access the AutoRAG Dashboard UI for interactive exploration:
    ```bash
    DASHBOARD_URL=$(oc get route autorag-dashboard -n <namespace> -o jsonpath='{.spec.host}')
    echo "https://${DASHBOARD_URL}/runs/<run-name>"
    ```

### Phase 5: Generate Notebook for Winning Pattern

13. Generate a notebook implementing the winning RAG pattern:
    ```bash
    oc get autoragrun <name> -n <namespace> \
      -o jsonpath='{.status.winnerNotebook}' > winning-rag-pattern.ipynb
    ```

14. The generated notebook includes:
    - Document loading and chunking with the winning parameters
    - Vector store setup with the optimal embedding model
    - Retrieval pipeline with the winning strategy and top_k
    - Generation chain with the configured LLM
    - Evaluation cells to verify performance on new queries

15. Recommend next steps:
    - Import notebook into a Workbench for further experimentation
    - Deploy the winning pattern as an OGX server (link to `ogx-rag-builder` skill)
    - Schedule periodic re-optimization as documents grow

## Output Format

```
# AutoRAG Optimization Report

## ⚠️ Technology Preview Notice
AutoRAG is a Technology Preview feature. Results should be validated before production use.

## Run Summary
- Run Name: {run-name}
- Namespace: {namespace}
- Duration: {elapsed-time}
- Total Trials: {count}
- Document Corpus: {source} ({file-count} files, {total-size})

## Leaderboard (Top 5)

| Rank | Chunking | Retrieval | Embedding | Faithfulness | Relevancy | Precision | Overall |
|------|----------|-----------|-----------|--------------|-----------|-----------|---------|
| 1 🏆 | {method} | {strategy} | {model} | {score} | {score} | {score} | {score} |
| 2    | {method} | {strategy} | {model} | {score} | {score} | {score} | {score} |
| 3    | {method} | {strategy} | {model} | {score} | {score} | {score} | {score} |
| 4    | {method} | {strategy} | {model} | {score} | {score} | {score} | {score} |
| 5    | {method} | {strategy} | {model} | {score} | {score} | {score} | {score} |

## Winner Configuration
- **Chunking**: {type}, chunk_size={size}, overlap={overlap}
- **Retrieval**: {strategy}, top_k={k}, {extra_params}
- **Embedding**: {model-name}
- **Overall Score**: {score}

## Key Insights
1. {Insight about which parameter had the most impact}
2. {Insight about diminishing returns or trade-offs}
3. {Insight about corpus-specific findings}

## Generated Artifacts
- Notebook: {path-to-notebook}
- Dashboard: {dashboard-url}

## Next Steps
- {Import notebook into Workbench}
- {Deploy as OGX server for production use}
- {Re-run optimization after adding new documents}
```

## Safety Constraints

- Do not run optimization against production inference endpoints under heavy load — optimization generates many concurrent requests
- Warn the user about compute costs — AutoRAG runs may consume significant CPU/memory and GPU time for embedding
- Do not automatically deploy the winning configuration to production — always require explicit user confirmation
- Respect namespace resource quotas — recommend appropriate resource requests based on corpus size
- Do not expose evaluation queries or ground truth data outside the namespace
- Warn that Technology Preview results may not be reproducible across RHOAI versions

## Disconnected Environment Notes

- **AutoRAG images**: Mirror the AutoRAG controller and worker images:
  ```yaml
  mirror:
    additionalImages:
      - name: registry.redhat.io/rhoai/autorag-controller-rhel9:latest
      - name: registry.redhat.io/rhoai/autorag-worker-rhel9:latest
  ```
- **Embedding models**: All embedding models referenced in the search space must be deployed locally — no external API calls
- **Document corpus**: Must be available on a PVC or local S3 (MinIO); external URLs are not reachable
- **Dashboard UI**: The AutoRAG dashboard is served from within the cluster and does not require external connectivity
- **Notebook generation**: Generated notebooks reference internal endpoints only — no external dependencies
