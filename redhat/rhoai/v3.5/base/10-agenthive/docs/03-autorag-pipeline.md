# 03 — AutoRAG pipeline

Build-time search for RAG chunking/embedding/retrieval settings.

Quick commands: [../autorag/run-autorag.md](../autorag/run-autorag.md).

There is no `AutoRAGRun` CRD. The mechanism is the DSPA managed pipeline `documents-rag-optimization-pipeline` in namespace `rfp-agent`. Reuse that DSPA; change **run parameters**, not the DSPA object-storage bucket.

## RFP agent

- MinIO bucket `rfp-agent-knowledge` with `input_data/` from `agents/rfp-agent/corpus/`
- `benchmark_rhoai.json` at the bucket root (OpenShift AI questions)
- Connection secrets `autorag-s3-connection` and `autorag-llama-stack`
- Payload: [`../autorag/rfp-run.json`](../autorag/rfp-run.json) — test data `benchmark_rhoai.json`
- Trigger (one-shot, not PostSync): `python3 platform/scripts/trigger-autorag.py --payload platform/autorag/rfp-run.json`
- After Succeeded: set `OGX_VECTOR_STORE_ID` on **`agents/rfp-agent/sandbox.yaml`** only

Do not edit `platform/deploy/base/sandbox.yaml`.

Gemini `remote::` models are typed `llm`, not `embedding`. AutoRAG search-space preparation requires an embedding-typed model (`inline::sentence-transformers` / nomic on CPU).
