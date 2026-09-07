# 07 — Corpus management

Knowledge corpora live in git per agent. There is no `platform/corpus/` directory.

| Agent | Corpus path | Vector store | MinIO bucket | Ingest Job |
|-------|-------------|--------------|--------------|------------|
| rfp-agent | `agents/rfp-agent/corpus/` | `rfp_knowledge_v1` | `rfp-agent-knowledge` | `corpus-ingest` |

Jobs run in namespace `rfp-agent` (OGX / MinIO credentials live there).

PostSync Job `purge-retired-knowledge` deletes leftover stores/buckets listed in that Job (`ask_brent_knowledge_v1`, `ask-brent-knowledge`) and must not touch `rfp_knowledge_v1` or `rfp-agent-knowledge`. There is no ingest Job that recreates the retired store.

## Add or update documents

1. Put markdown under the agent’s category folders. Skip `README.md` files; ingest ignores them. Official OpenShift AI 3.3/3.4/3.5 conversions: `agents/rfp-agent/corpus/11-openshift-ai/`.
2. Commit and push. The matching infra PostSync Job clones `main` and:
   - uploads `*.md` to that agent’s MinIO bucket `input_data/`
   - runs `platform/scripts/ingest-corpus.py` with `CORPUS_DIR` and `VECTOR_STORE_NAME` set for that store

Local ingest (RFP):

```bash
export OGX_SERVICE_URL="http://rfp-ogx-service.rfp-agent.svc.cluster.local:8321"
export CORPUS_DIR="$(pwd)/agents/rfp-agent/corpus"
export VECTOR_STORE_NAME="rfp_knowledge_v1"
python3 platform/scripts/ingest-corpus.py
```

## Benchmark file

Place JSON under `test-data/`. Ingest copies it to the bucket **root** (not into the named vector store). RFP AutoRAG must use `benchmark_rhoai.json` (OpenShift AI questions). `benchmark_data.json` is the legacy sandbox-blog set — do not optimize RFP RAG against it.

| Agent | Benchmark path | Bucket object |
|-------|----------------|---------------|
| rfp-agent | `agents/rfp-agent/corpus/test-data/benchmark_data.json` (legacy sandbox Qs) and `benchmark_rhoai.json` (OpenShift AI RFP/RFI) | `benchmark_data.json` and `benchmark_rhoai.json` |
