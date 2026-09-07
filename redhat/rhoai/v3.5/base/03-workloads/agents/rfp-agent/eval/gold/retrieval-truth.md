# Retrieval truth — named store vs AutoRAG winner

Checked 2026-08-24 on cluster `afred-34-test`, pod `rfp-agent`, no `operatingMode` patches.

## What the sandbox is using

`/sandbox/.hermes/rag-config.json`:

```json
{
  "ogx_base_url": "http://rfp-ogx-service.rfp-agent.svc.cluster.local:8321",
  "vector_store_id": "vs_ad383c2f-9c50-4456-bfd2-b0bb6260732d",
  "top_k": 5
}
```

That id is the AutoRAG winner pinned on [sandbox.yaml](../../../sandbox.yaml) (`OGX_VECTOR_STORE_ID`).

## Store inventory (OGX `/v1/vector_stores`)

| Store | Name | `file_counts.completed` | `/v1/vector-io/query` | `/v1/vector_stores/{id}/search` |
|-------|------|-------------------------|------------------------|----------------------------------|
| `vs_ad383c2f-9c50-4456-bfd2-b0bb6260732d` | *(empty name)* | **0** (files list empty) | **hits** with corpus `document_id`s | **200** |
| `vs_9bacc92d-4e67-4345-b080-21f68f26cb25` | `rfp_knowledge_v1` | **38** (2026-08-24 official 3.3–3.5 docs ingest) | **404** not in `vector_dbs` (expected until AutoRAG re-index) | **400** not in `vector_dbs` |

`file_counts` 0 on the winner is expected for an AutoRAG unnamed collection. The vectors are still searchable via vector-io. The named ingest store is visible to the Files API and **not** registered for vector-io.

## Same questions, both ids

Queries used: disconnected, vLLM runtime, AutoRAG, Praxis name, TrustyAI, GPU-hour price, workbenches/DSP, NVIDIA+AMD serving.

- **Winner:** 3 chunks per query. Relevant `document_id`s for serving, RAG, naming, TrustyAI, disconnected (gpu-hybrid). Workbench/DSP retrieved **off-topic** chunks (training cert, partners). GPU-hour price still retrieved GPU/partner docs — the **agent** must abstain, retrieval will not.
- **Named `rfp_knowledge_v1`:** HTTP 404 `Vector Store not found. Use client.vector_dbs.list()`.

## Decision

Live retrieval still uses AutoRAG winner `vs_ad383c2f-9c50-4456-bfd2-b0bb6260732d` until run `autorag-rfp-agent-rhoai-docs` (`run_id=1c61d027-7400-41c1-8618-e7a1dce54649`, started 2026-08-24) Succeeds and `OGX_VECTOR_STORE_ID` is pinned on `agents/rfp-agent/sandbox.yaml`.

Do **not** re-run AutoRAG on the old 38-question sandbox-blog benchmark. After gold eval exists, a later index job can register the named ingest collection into `vector_dbs` so ingest and query share one id.

Open WebUI docs must not say traffic goes to `rfp_knowledge_v1` for retrieval. Retrieval is the pinned winner. Ingest still writes the named store.
