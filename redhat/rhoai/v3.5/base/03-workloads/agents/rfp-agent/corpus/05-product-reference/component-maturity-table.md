---
title: Red Hat AI Component Maturity Table
date: 2026-08-17
source: Blueprint Table 4 (July 2026), field positioning
product_area: All Red Hat AI
---

# Component Maturity Table

## Production-Ready (GA) Today

| Component | Product | Notes |
|-----------|---------|-------|
| OpenShift Sandboxed Containers | RHOAI / OperatorHub | Kata VM isolation, GA |
| vLLM Model Serving | Red Hat OpenShift AI | Multi-backend (CUDA, ROCm, XPU, CPU) |
| llm-d Router | Gateway API Inference Extension | CNCF Sandbox, GA |
| SPIFFE/SPIRE | Workload Identity | JWT-SVID, auto-rotating |
| NeMo Guardrails | Red Hat AI | Input/output guardrails |
| TrustyAI Guardrails Orchestrator | Red Hat AI | Output safety filtering |
| Red Hat AI gateway | Red Hat AI | Auth, quota, basic routing |

## Technology Preview / Emerging

| Component | Status | Target |
|-----------|--------|--------|
| NVIDIA OpenShell | Dev/Tech Preview | RHOAI 3.5/3.6 (H2 2026) |
| MCP Gateway (Kuadrant) | Technology Preview | — |
| Garak (red teaming) | Technology Preview | — |
| agent-sandbox CRD | Upstream v1beta1 (SIG Apps) | — |
| Semantic routing (AI gateway) | Emerging/preview | Roadmap |
| OGX (Agent-as-a-Service) | OpenShift AI 3.5 EA | — |
| AutoRAG | Technology Preview | RHOAI 3.4+ |
| Confidential Containers | GA on silicon | Runtime overhead caveat |

## Reading Rule

- Build base decisions on the GA column
- Adopt from preview behind pinned versions and feature gates
- Revisit at each release
