---
title: Red Hat OpenShift AI version and feature status (3.3, 3.4, 3.5)
date: 2026-08-24
source: Official Red Hat Documentation — Self-Managed release notes 3.3, 3.4, 3.5
product_area: Red Hat OpenShift AI
---

# Understanding OpenShift AI versions 3.3, 3.4, and 3.5

> Reference study guide for official Self-Managed release notes.
> Converted 2026-08-24. Re-check the portal before a customer submission.

## Sources & Relationships

| # | Source | URL | Contribution |
|---|--------|-----|----------------|
| 1 | OpenShift AI 3.3 release notes (3.3.6) | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html-single/release_notes/index | Migration from 2.25.4; MaaS and NeMo Guardrails as Technology Preview; hardware profiles GA |
| 2 | OpenShift AI 3.4 release notes (3.4.2) | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/release_notes/release_notes | MaaS GA; NeMo Guardrails fully supported; MLflow fully supported; AutoRAG Technology Preview |
| 3 | OpenShift AI 3.5 EA2 release notes | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html-single/release_notes/index | **Early Access**, not GA. Responses API GA on OGX; MaaS/llm-d enhancements |

**Source:** each row’s release notes, overview and new-features / Technology Preview chapters.

## Module 1: Which release to name in an RFP

| Version | Product name | Support posture in these notes |
|---------|--------------|--------------------------------|
| 3.3 | Red Hat OpenShift AI Self-Managed | GA stream (notes for 3.3.6). Last fast-channel release; Red Hat recommends `stable-3.x` after upgrade. |
| 3.4 | Red Hat OpenShift AI Self-Managed | GA stream (notes for 3.4.2). |
| 3.5 | Red Hat OpenShift AI Self-Managed | **Early Access (EA2 / EA1).** Technology Preview chapter is titled for 3.5 EA2. Do **not** claim 3.5 is Generally Available from these notes. |

3.0 made a direct upgrade from 2.25 technically complex. **3.3.2 is the first 3.x that supports migration from 2.25.4 (and later).** Upgrades 3.2 → 3.3 are fully supported. New 3.3 installs: OpenShift Container Platform **4.19.9 or later**, channel `stable-3.x`.

**Source:** 3.3 release notes, Chapter 1 Installation and upgrade path; 3.5 notes title “3.5 EA2”.

> **Key Insight:** If the customer is on OpenShift AI 2.25 EUS, the documented migration target in these notes is **3.3**, not a skip-straight-to-3.5 claim.

## Module 2: Feature status across 3.3 → 3.4 → 3.5

Technology Preview is **not** supported with Red Hat production SLAs and is not recommended for production (standard TP disclaimer in every notes book).

| Capability | 3.3 | 3.4 GA | 3.5 EA2 |
|------------|-----|--------|---------|
| Hardware profiles (node targeting for workbenches / serving) | GA (from 3.0; replaces accelerator profiles) | GA | GA |
| Kubeflow Trainer v2 | GA | GA | GA |
| Models-as-a-Service (MaaS) | **Technology Preview** | **Generally Available** | GA (3.4 GA carried forward); extra MaaS items still TP (see below) |
| NeMo Guardrails | **Technology Preview** | **Fully supported** | Fully supported (3.4) |
| MLflow | TP / Dev Preview history | **Fully supported**; `mlflowoperator` managed on DataScienceCluster | Managed component; IBM Power extras in 3.5 |
| AutoRAG | not called GA in 3.3 notes | **Technology Preview** (one 3.5 notes passage still says Developer Preview in an older subsection — treat as **TP per 3.4 GA chapter** unless a later GA note exists) | Still discussed as TP; Power architecture enablement |
| AutoML | — | **Technology Preview** | TP (Power enablement mentioned) |
| Distributed Inference with llm-d | used by MaaS (MaaS is TP in 3.3) | Serving path; several llm-d extras are TP | llm-d scheduler/metrics enhancements; some llm-d features remain TP |
| vLLM as MaaS runtime | — | **Technology Preview** (`vLLMDeploymentOnMaaS` flag) | TP |
| External OIDC for MaaS | — | **Technology Preview** | TP |
| MaaS observability / showback dashboard | — | **Technology Preview** | TP |
| MaaS routing to OpenAI / Anthropic | — | **Technology Preview** | TP |
| Responses API on OGX | Llama Stack Responses API was TP in 3.4 notes | TP (Llama Stack / Responses API) | **Generally Available on OGX** (3.5 EA2). 3.5 EA1 notes: OGX **replaces Llama Stack** |
| EvalHub UI / SDK / MCP | — | EvalHub SDK/CLI and Evaluation Stack UI = TP | EvalHub MCP server and dashboard thresholds = TP |

**Source:** 3.3 Ch. 3 new features; 3.4 Ch. 2 GA features and Ch. 3 TP; 3.5 EA2 Ch. 2 and Ch. 3 TP.

## Module 3: MaaS — what is GA vs still preview

**GA (from 3.4):** subscription-based access, token quotas and rate limits, self-service API keys, centralized authz for the GA MaaS control plane, llm-d as the documented MaaS serving integration.

**Still Technology Preview (called out in 3.4 GA and 3.5 EA notes):** vLLM runtime **on MaaS**, external OIDC, observability/showback dashboard, routing to external providers (OpenAI, Anthropic).

3.3 used a **tier-based** MaaS model. 3.4 **redesigned subscriptions** to replace that tier model.

MaaS in 3.3 docs requires LeaderWorkerSet Operator and distributed inference with llm-d. Enabling is via DataScienceCluster `modelsAsService` (see MaaS product page).

**Source:** 3.4 release notes “Models-as-a-Service now Generally Available”; 3.3 MaaS book TP banner; 3.5 EA2 subscriptions tab enhancement.

## Module 4: Naming for customer text

- Product: **Red Hat OpenShift AI** (Self-Managed when the RFP is on-prem / customer-managed OpenShift).
- Inference engine: **vLLM** inside OpenShift AI — not a separate Red Hat SKU.
- Distributed inference: **llm-d** (community name).
- Gateway product name remains **Red Hat AI gateway** in the field naming table; these OpenShift AI books discuss MaaS inference gateway and Kubernetes Gateway for llm-d. Do not write “Praxis”.
- **OGX** is the 3.5 name that **replaces Llama Stack** (3.5 EA1 notes). Customer-facing: OGX / Agent-as-a-Service / Responses API as part of OpenShift AI. Responses API is **GA on OGX in 3.5 EA2** only — if the customer is on 3.4, it is Technology Preview.

**Source:** 3.5 EA1 “OGX (which replaces Llama Stack)”; 3.5 EA2 “Responses API is generally available on OGX”; `product-naming-canonical.md`.
