---
title: Red Hat OpenShift AI model serving, llm-d, and Models-as-a-Service
date: 2026-08-24
source: Official 3.3 MaaS book; 3.4 and 3.5 release notes; 3.5 llm-d scheduler chapter
product_area: Red Hat OpenShift AI
---

# Understanding OpenShift AI serving, llm-d, and MaaS

> Official docs, not blogs. Status always includes the version (3.3 / 3.4 GA / 3.5 EA).

## Sources & Relationships

| # | Source | URL |
|---|--------|-----|
| 1 | 3.3 Govern LLM access with MaaS | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/govern_llm_access_with_models-as-a-service/deploy-and-manage-models-as-a-service_maas |
| 2 | 3.4 release notes (MaaS GA) | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.4/html-single/release_notes/release_notes |
| 3 | 3.5 llm-d scheduler | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/deploy_models_using_distributed_inference_with_llm-d/configuring-llm-scheduler |
| 4 | 3.5 architecture (model serving) | architecture-of-openshift-ai-self-managed_install |

## Module 1: Two serving stories

1. **Single-model / predictive serving** — KServe (`InferenceService`), RawDeployment or Knative, authenticated endpoints (3.5 book *Deploy predictive models using single model serving platform*).
2. **Distributed Inference with llm-d** — `LLMInferenceService` / `LLMInferenceServiceConfig`; vLLM engine pods, Endpoint Picker (EPP). 3.5 notes document migration from vLLM-based InferenceService to LLMInferenceService (see also Red Hat article 7141739).

vLLM is the **runtime engine inside OpenShift AI**, not a standalone Red Hat product name.

**Source:** 3.5 portal serving titles; 3.5 notes migration guide bullet; product naming table.

## Module 2: llm-d scheduler (3.5)

Scheduler settings go on `LLMInferenceService` via `endpointPickerConfig`:

- **Inline** — embed `EndpointPickerConfig` in the service spec
- **ConfigMap** — share one scheduler config across services

This **replaces** passing large YAML through the scheduler `--configText` argument (3.5 EA2 notes).

Disconnected book: llm-d needs OpenShift **4.20+**, plus cert-manager, Connectivity Link, Leader Worker Set.

**Source:** 3.5 llm-d scheduler chapter; 3.5 EA2 “Simplified configuration for Distributed Inference”; disconnected requirements.

## Module 3: Models-as-a-Service

| Version | MaaS status |
|---------|-------------|
| 3.3 | **Technology Preview.** Not production-supported. Requires LeaderWorkerSet; only **Distributed inference with llm-d** runtime exposes “Publish as MaaS endpoint”. Enable via DataScienceCluster `modelsAsService`. Tiers in ConfigMap `tier-to-group-mapping` in `redhat-ods-applications`. |
| 3.4 | **Generally Available.** Subscriptions **replace** the 3.3 tier model. Self-service API keys. Token quotas and rate limits. |
| 3.5 EA | MaaS remains the 3.4 GA control plane; UI adds a Subscriptions tab. Several **MaaS add-ons stay Technology Preview** (vLLM-on-MaaS, external OIDC, showback dashboard, external providers). |

**Source:** 3.3 MaaS TP banner and deploy chapter; 3.4 “MaaS now Generally Available”; 3.5 EA2 Subscriptions tab.

> **Key Insight:** “Does OpenShift AI do MaaS?” → Yes from **3.4 GA**. On **3.3** it is Technology Preview. vLLM **as the MaaS runtime** is still Technology Preview in 3.4/3.5 notes.

## Module 4: What to mark HUMAN

- Exact token prices, SKU lists, GPU-hour rates — not in these books.
- Whether a given customer’s cluster is 4.19 vs 4.20 (llm-d gate).
