---
title: Red Hat OpenShift AI guardrails, MLflow, AutoRAG (official 3.3–3.5)
date: 2026-08-24
source: Official release notes 3.3–3.5; NeMo Guardrails 3.5 book
product_area: Red Hat OpenShift AI
---

# Understanding OpenShift AI safety, evaluation, and AutoRAG

## Sources

| Source | URL |
|--------|-----|
| 3.5 NeMo Guardrails | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/enabling_ai_safety_with_guardrails/enabling-ai-safety-with-nemo-guardrails_nemo-guardrails |
| 3.4 / 3.5 release notes | html-single release_notes for each version |

## Module 1: NeMo Guardrails

Deployed via **TrustyAI** in OpenShift AI.

| Version | Status |
|---------|--------|
| 3.3 | **Technology Preview** |
| 3.4 | **Fully supported** (no longer TP) |
| 3.5 | Fully supported (3.4 GA). 3.5 EA2 TP: NeMo Guardrails integration with **MCP Gateway** for agent tool-call enforcement (standalone mode without full TrustyAI stack is described in 3.5 TP notes). |

3.5 procedure book: rails for sensitive data detection, content filtering, custom validation; `/v1/guardrail/checks` validates messages **without** generating an LLM response. Internal detectors (Presidio, regex) can run **without** a configured LLM and without external network — relevant for disconnected checks.

**Source:** 3.3/3.4 notes status sentences; 3.5 guardrails chapter (checks endpoint and detector notes); 3.5 EA2 TP MCP Gateway integration.

## Module 2: MLflow

| Version | Status |
|---------|--------|
| Before 3.4 | Technology Preview / Developer Preview (per 3.4 notes) |
| 3.4 | **Fully supported.** `mlflowoperator` on DataScienceCluster; dashboard flag deprecated |
| 3.5 | Same managed component; SDK in workbench images; IBM Power enablement in EA notes |

**Source:** 3.4 “MLflow is fully supported”.

## Module 3: AutoRAG

| Version | Status in official notes |
|---------|--------------------------|
| 3.4 GA TP chapter | **Technology Preview.** Dashboard to configure runs, leaderboard of RAG patterns, notebooks for indexing/inference. |
| 3.5 EA | Still not described as GA. Power architecture enablement. Known issue RHOAIENG-64768: default AutoML/AutoRAG pipeline image digests can ImagePullBackOff. |

Do **not** tell a customer AutoRAG is GA. Do **not** invent a faithfulness score from this repo’s cluster as a product claim.

**Source:** 3.4 TP “Automate RAG optimization with AutoRAG”; 3.5 known issues AutoML/AutoRAG image pull.

## Module 4: EvalHub (preview)

3.4 TP: EvalHub client SDK/CLI; Evaluation Stack UI.
3.5 EA2 TP: EvalHub MCP server for coding agents; pass/fail thresholds on dashboard eval runs.

**Source:** 3.4 and 3.5 Technology Preview chapters.
