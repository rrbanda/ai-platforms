# Running AutoRAG — RHOAI 3.5

Use AutoRAG to find the optimal RAG configuration for a knowledge corpus.
This is a build-time activity that produces an optimized Milvus vector store.

For full details see [platform/docs/03-autorag-pipeline.md](../docs/03-autorag-pipeline.md).

## Prerequisites

- [x] OGX running with `inline::sentence-transformers` provider (registers embedding model type)
- [x] OGX running with `remote::gemini` provider (for foundation model)
- [x] OGX running with `remote::milvus` provider (for vector storage)
- [x] Matching MinIO bucket has `input_data/` **and** `benchmark_data.json` at the bucket root
- [x] DataSciencePipelinesApplication in `rfp-agent` with `managedPipelines: {}`
- [x] OGX connection secret `autorag-llama-stack`
- [x] S3 connection secret for that bucket (`autorag-s3-connection`)

## Trigger from git (RFP)

After corpus ingest has uploaded official OpenShift AI docs and `benchmark_rhoai.json`:

```bash
python3 platform/scripts/trigger-autorag.py \
  --payload platform/autorag/rfp-run.json
```

If your current `oc` context is not the ROSA cluster, set `OC_CONTEXT` to the afred-34-test admin context before running the script.

Payload: bucket `rfp-agent-knowledge`, secret `autorag-s3-connection`, test object `benchmark_rhoai.json` (OpenShift AI questions). Do **not** optimize against the old sandbox-blog `benchmark_data.json`.

Same embedding/LLM settings (`nomic-embed-text-v1.5`, `gemini-2.5-flash`, 4 patterns). AutoRAG makes sense here because the agent’s live retrieval is vector-io (AutoRAG winner), while named `rfp_knowledge_v1` 404s on vector-io.

## Quick checks

```bash
# 1. Verify OGX has embedding-typed models
oc exec -n rfp-agent rfp-agent -c agent -- \
  curl -s http://rfp-ogx-service:8321/v1/models | \
  python3 -c "import json,sys; d=json.load(sys.stdin)['data']; \
  print([m['id'] for m in d if m.get('custom_metadata',{}).get('model_type')=='embedding'])"

# 2. Verify pipeline is registered
POD=$(oc get pods -n rfp-agent --no-headers | grep "ds-pipeline-dspa" | grep "2/2" | head -1 | awk '{print $1}')
oc exec -n rfp-agent "$POD" -c ds-pipeline-api-server -- \
  curl -sk https://localhost:8888/apis/v2beta1/pipelines
```

## What AutoRAG Does

1. **Documents discovery** — finds docs in S3 `input_data/` folder
2. **Text extraction** — converts markdown/PDF to plain text chunks
3. **Test data loader** — loads `benchmark_data.json`
4. **Search space preparation** — validates models, builds parameter grid
5. **RAG templates optimization** — tests chunking/embedding/retrieval combos
6. **Leaderboard evaluation** — scores patterns, produces ranked results

## Output

After completion, AutoRAG produces:

- A **leaderboard** ranking RAG patterns by the optimization metric
- An **indexing notebook** to build the production Milvus index
- An **inference notebook** showing how to query the optimized pipeline
- A `vector_store_id` that the agent uses for retrieval (unnamed collection; `file_counts` 0 is expected)

## Post-Optimization

1. Select the best pattern from the leaderboard
2. Note the `vector_store_id`
3. Set `OGX_VECTOR_STORE_ID` on the matching agent Sandbox in git (`agents/rfp-agent/sandbox.yaml`) and push.
   Do not edit `platform/deploy/base/sandbox.yaml` (not the GitOps agent path).

## Key Insight: Why inline::sentence-transformers

AutoRAG's `search-space-preparation` step calls `ogx_client.models.list()` and
filters by `model_type == "embedding"`. The `remote::gemini` provider marks ALL
models as `llm` type (no override mechanism exists). Only providers like
`inline::sentence-transformers` properly register models as type `embedding`.

This is the single most important configuration detail for making AutoRAG work
without GPU infrastructure.
