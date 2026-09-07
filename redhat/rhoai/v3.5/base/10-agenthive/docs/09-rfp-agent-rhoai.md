# 09 — rfp-agent job spec (OpenShift AI RFP / RFI)

This is the product spec for making `rfp-agent` useful on **any OpenShift AI RFP or RFI**. It is the Phase 0 gate from the readiness plan: do not treat blog Q&A scores as the job.

Related: [agent README](../../agents/rfp-agent/README.md), [gold fixtures](../../agents/rfp-agent/eval/gold/README.md), [corpus](../../agents/rfp-agent/corpus/README.md), [Open WebUI](08-open-webui.md), [eval](05-evaluation-mlflow.md).

## Success

A sales user drops an OpenShift AI **RFP or RFI** into Open WebUI (PDF / DOCX / XLSX / paste). The agent returns a **complete, grounded** package:

- Every question or requirement is answered, scaffolded, or explicitly marked human-only
- Product names match [product-naming-canonical.md](../../agents/rfp-agent/corpus/05-product-reference/product-naming-canonical.md)
- Factual claims cite a real `document_id`
- Pricing, legal, unapproved customer claims, and missing corpus cells are **never invented**

Incomplete is success. Fabricated completeness is failure.

## In scope

Red Hat OpenShift AI and the Red Hat AI capabilities sold with it, named as products:

- OpenShift AI platform: dashboard, workbenches, Data Science Pipelines, DataScienceCluster components
- Serving: KServe, vLLM **inside** OpenShift AI, llm-d, accelerators, MaaS
- Training / customization: distributed training, InstructLab, fine-tune vs RAG
- Data / RAG: connections, vector stores, AutoRAG
- Catalog / model registry / MLflow / EvalHub
- Guardrails: TrustyAI, NeMo Guardrails, Garak (with GA vs Technology Preview)
- Red Hat AI gateway (never “Praxis”), quotas
- Disconnected / GPU operators / Kueue as they appear on OpenShift AI questionnaires
- Support tiers and subscription **shape** (not SKU prices)

## Out of scope unless the questionnaire asks

- Generic OpenShift (SDN, Operators-at-large) with no AI angle
- Ansible-only, ACS-only, or RHEL-only RFPs
- Hermes / NVIDIA OpenShell / agent-sandbox internals (answer only if the RFP asks about agent isolation)
- Live cluster mutation; GitOps remains the only write path

## RFI vs RFP vs hybrid

| Kind | What inbound looks like | What to return |
|------|-------------------------|----------------|
| **RFI / questionnaire** | Excel/Word matrices, Yes/No/Partial, “describe architecture” | Filled matrix with citations. Not a 40-page proposal. |
| **RFP / proposal** | Customer-prescribed narrative sections | Mirror **their** outline. Mark `[AUTO-GENERATED]`, `[SCAFFOLD]`, `[HUMAN INPUT REQUIRED]`. |
| **Hybrid** | Both in one package | Split the package at intake. Matrix + narrative. |

The soul must classify **document job** (RFI / RFP / hybrid) before choosing drafting templates. Technology vs services is a second axis, not a substitute for RFI vs RFP.

## Non-negotiables

1. Canonical names. Never Praxis, Kagenti, “vLLM as a Red Hat product,” or “Red Hat OpenShell.”
2. Status honesty. GA vs Technology Preview vs EA from the maturity table. When unsure: `[NEEDS HUMAN INPUT]`.
3. No invented prices, discounts, legal terms, SLAs beyond published support tiers, or named-customer metrics that are not in corpus.
4. Retrieval before claims. If `rh-knowledge-retrieval` returns nothing, abstain.
5. Open WebUI is the sales front door. Uploads do not land in `/sandbox`. Use extracted chat text. Hermes dashboard Files panel is the disk path.
6. Phase pauses are conversational (“Proceed?”). Open WebUI has no Hermes `/v1/runs/{id}/approval` cards. Do not block the workflow on native tool-approval HITL.
7. Isolation: this agent’s store only.

## UX

- **Open WebUI** model `rfp-agent`: paste, attach, or multi-file extract in chat.
- **Hermes dashboard**: Files panel → `/sandbox/data`.
- Conversational HITL is enough for phase gates. Native approve/deny is dashboard-only.

## Measurement (what “high performing” means)

Do not use README Faithfulness 86% as a gate until a Job reproduces it. The live eval set is [eval/gold/benchmark_rhoai.json](../../agents/rfp-agent/eval/gold/benchmark_rhoai.json): taxonomy questions, RFI rows, naming traps, and abstain-correctly traps.

Gates after a gold dry-run:

- Grounded rows cite a real filename
- Absent-corpus rows are HUMAN / UNVERIFIABLE, not fluent fiction
- Zero forbidden product names in customer-facing text

## Retrieval pin

The sandbox may set `OGX_VECTOR_STORE_ID` to the AutoRAG winner. That winner can show `file_counts` 0 and still answer `/v1/vector-io/query`. The named ingest store `rfp_knowledge_v1` can list 30 files and still **404** on vector-io. Pin the store that **vector-io can search**. See [retrieval-truth.md](../../agents/rfp-agent/eval/gold/retrieval-truth.md). Do not re-run AutoRAG on the old 38-question sandbox-blog set.
