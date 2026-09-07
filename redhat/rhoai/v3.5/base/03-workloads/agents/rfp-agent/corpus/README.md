# Corpus — RFP knowledge base

Documents live in **this directory** (`agents/rfp-agent/corpus/`). There is no `platform/corpus/`.

Add markdown under the numbered category folders. Ingest ignores `README.md`.

On GitOps sync, `platform/gitops/infra/ingest/ingest-job.yaml` uploads `*.md` to MinIO and runs `platform/scripts/ingest-corpus.py`. Official OpenShift AI 3.3/3.4/3.5 conversions: [`11-openshift-ai/`](11-openshift-ai/). Details: [platform/docs/07-corpus-management.md](../../../platform/docs/07-corpus-management.md).
