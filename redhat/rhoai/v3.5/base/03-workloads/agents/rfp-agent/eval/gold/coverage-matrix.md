# Corpus coverage vs OpenShift AI taxonomy

Scored 2026-08-24 against `agents/rfp-agent/corpus/` (**33** knowledge markdown files after fills) plus naming and maturity tables. Gold rows: [rfi-answer-key.json](rfi-answer-key.json). Live retrieval still uses the AutoRAG winner until vector-io is re-indexed.

**Legend:** grounded = enough to AUTO-cite; partial = scaffold only; absent = HUMAN until sourced; human = stay HUMAN even after fill.

| Cell | Score (git corpus) | What exists | Fill vs stay-human |
|------|--------------------|-------------|--------------------|
| platform-operators | **partial** (was absent) | `openshift-ai-components.md` (DSC, dashboard, workbenches, pipelines). Not on live winner yet. | Keep; re-index to retrieve. |
| serving-inference | **partial / grounded** | `red-hat-ai-inference-capabilities.md`; KServe named on DSC table. | Scaffold KServe CR details. |
| training-customization | **partial** | LoRA in RAG doc; InstructLab in `red-hat-responsible-ai.md`. | SCAFFOLD Q8; no extra fill. |
| data-rag | **grounded** | AutoRAG + EvalHub. | Keep. |
| catalog-registry | **partial** | Catalog + MLflow; ModelRegistry on DSC table. | Scaffold CR how-to. |
| guardrails | **grounded** | Safety stack + maturity (Garak = TP). | Keep. |
| maas-gateway | **grounded** | MaaS + naming (Red Hat AI gateway). | Keep. Forbidden: Praxis. |
| disconnected-gpu | **partial** | `openshift-ai-disconnected.md` + gpu-hybrid + gov case study. No NFD/GPU-operator how-to. | Stay human for site mirror URLs. |
| identity-security | **partial / grounded** | Vuln + TSSC. Not RHOAI RBAC. | Human for cluster RBAC. |
| lifecycle | **absent** | Support tiers only. | **Stay human.** |
| commercial | **human** | No GPU-hour list. | **Stay human.** |
| evidence | **partial** | Brochure case studies. | **Stay human** for named metrics. |

## Skill overclaim

`rh-knowledge-retrieval` categories were rewritten to match files that exist. Pricing/SOW libraries are not claimed.

## Golden-set mismatch (old 38-question file)

[benchmark_data.json](../../corpus/test-data/benchmark_data.json) still points at missing `document_id`s. Use [benchmark_rhoai.json](benchmark_rhoai.json).

## Fills landed in git

1. `02-platform/openshift-ai-components.md`
2. `02-platform/openshift-ai-disconnected.md`
3. `08-rfp-examples/rfi-questionnaire-response-pattern.md`

Commercial prices and fake win metrics were not added.
