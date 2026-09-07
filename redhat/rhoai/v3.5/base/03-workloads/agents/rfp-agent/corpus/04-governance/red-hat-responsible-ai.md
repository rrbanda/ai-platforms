---
title: Red Hat Responsible AI Principles
date: 2026-08-19
source: Red Hat AI strategy documentation, InstructLab project, asago project
product_area: AI/ML, Governance
---

# Red Hat Responsible AI Principles

## Core Principle

No black-box models. Transparency at every stage of the AI lifecycle — from training data provenance through inference-time decision-making.

Red Hat's minimum standard for "open source AI": open source-licensed model weights combined with open source software components. Proprietary model APIs do not qualify.

---

## InstructLab

Community-driven methodology for LLM contribution without full model retraining.

| Attribute | Detail |
|-----------|--------|
| Full name | Large-scale Alignment for chatBots (LAB) |
| License | Apache License 2.0 |
| Release cadence | Weekly model releases on Hugging Face |
| Contribution model | Domain experts submit skills and knowledge via taxonomy files |
| Training approach | Synthetic data generation + phased training (no full retraining required) |
| Repository | github.com/instructlab |

### How InstructLab Works

1. Contributors add skill or knowledge entries to a YAML taxonomy
2. Synthetic training data is generated from the taxonomy entries
3. Phased fine-tuning aligns the model to new capabilities incrementally
4. Updated model is validated and released weekly

---

## Granite Models

Developed by IBM Research. Open source-licensed foundation models with full dataset transparency.

| Attribute | Detail |
|-----------|--------|
| License | Apache License 2.0 |
| Provider | IBM Research |
| Dataset transparency | Training data sources documented and published |
| Variants | Code, Language, Time Series, Geospatial |
| Distribution | Hugging Face, RHEL AI |

---

## RHEL AI

Bootable RHEL image packaging Granite models with InstructLab for on-premise model customization.

- Single-node deployment for model fine-tuning and inference
- Ships as a bootable container image
- Includes InstructLab CLI for taxonomy-based customization
- GPU support for NVIDIA and AMD accelerators
- Enterprise lifecycle support from Red Hat

---

## asago (AI Safety And Governance Orchestration)

Launched 2026. Automates translation of AI governance policies into operational controls.

| Attribute | Detail |
|-----------|--------|
| License | Apache License 2.0 |
| Launch year | 2026 |
| Purpose | Policy-to-controls automation |
| Output formats | Kubernetes manifests, Terraform configurations, Ansible playbooks |

### Four Stages

1. **Risk mapping** — Identify AI system components, data flows, and stakeholders
2. **Risk assessment** — Score risks against governance framework requirements
3. **Risk mitigation** — Generate controls and guardrails configurations
4. **Production deployment** — Apply controls as infrastructure-as-code artifacts

### Compliance Framework Mapping

| Framework | Coverage |
|-----------|----------|
| NIST AI RMF | Full mapping across Govern, Map, Measure, Manage functions |
| OWASP LLM Top 10 | All 10 categories addressed |
| EU AI Act | Risk classification and corresponding control generation |

---

## TrustyAI

Open source toolkit for model explainability, bias detection, and fairness monitoring.

- Model explainability (LIME, SHAP)
- Bias detection across protected attributes
- Fairness monitoring with configurable metrics
- Drift tracking for production models
- Integrates with Red Hat OpenShift AI (RHOAI)

---

## Garak

LLM vulnerability scanning tool. Technology Preview status.

- Probes for prompt injection susceptibility
- Tests jailbreak resistance
- Detects data leakage vectors
- Evaluates hallucination tendencies
- Extensible plugin architecture for custom probes

---

## NeMo Guardrails

Runtime input/output guardrails for LLM applications.

- Topic control (prevent off-topic responses)
- Input filtering (block malicious prompts)
- Output filtering (prevent harmful or non-compliant responses)
- Hallucination reduction via fact-checking rails
- Configurable via Colang policy language

---

## Standards and Alliances

| Initiative | Status |
|-----------|--------|
| ISO 42001 (AI Management System) | Alignment in progress |
| Open Secure AI Alliance | Member (with NVIDIA) |
| InstructLab community | Co-founded with IBM |
| ComplianceAsCode | Active contributor |

---

## Summary Table

| Component | Function | License |
|-----------|----------|---------|
| InstructLab | Community LLM contribution | Apache 2.0 |
| Granite | Foundation models | Apache 2.0 |
| RHEL AI | Model deployment + customization | Subscription |
| asago | Governance automation | Apache 2.0 |
| TrustyAI | Explainability + fairness | Open source |
| Garak | Vulnerability scanning | Open source |
| NeMo Guardrails | Runtime guardrails | Open source |
