---
title: Red Hat AI Product Naming — Canonical Reference
date: 2026-08-17
source: Internal field positioning, Ann Marie Fred feedback (Aug 2026)
product_area: All Red Hat AI
---

# Red Hat AI Product Naming — Canonical Reference

## Correct Customer-Facing Names

| Internal / Upstream | Customer-Facing Name | Notes |
|---------------------|---------------------|-------|
| Praxis | **Red Hat AI gateway** | Never use "Praxis" in customer docs |
| Kagenti / AgentRuntime CRD | **DEPRECATED** — converged into OpenShell | Do not reference as current/future product |
| OpenShell | **NVIDIA OpenShell** | Open source, Apache-2.0; say "NVIDIA OpenShell" (Red Hat is a contributor) |
| Kata Containers (on OpenShift) | **OpenShift Sandboxed Containers** | The product name for Kata on OpenShift |
| Kuadrant/mcp-gateway | **MCP Gateway** | Technology Preview |
| OGX (formerly Llama Stack) | **Agent-as-a-Service / Responses API** | Part of OpenShift AI |
| llm-d | **llm-d** (CNCF Sandbox project) | Use as-is, it's the community name |
| vLLM on OpenShift | **Red Hat OpenShift AI** (with vLLM) | vLLM is the serving engine inside the product |
| TrustyAI | **TrustyAI** (part of Red Hat AI) | Keep the project name |
| Garak | **Garak** | Keep the project name, note as Technology Preview |
| NeMo Guardrails | **NeMo Guardrails** | NVIDIA project, not Red Hat |
| agent-sandbox API | **agent-sandbox CRD** | It is a lifecycle CRD, NOT an isolation API |
| AutoRAG | **AutoRAG** (part of Red Hat OpenShift AI) | Technology Preview in RHOAI 3.4+ |

## Status Terms

- **Generally Available (GA)** — production-ready, supported
- **Technology Preview** — available but not production-supported
- **Dev/Tech Preview** — early access, interface may change
- **Upstream** — community project, not productized

## Common Mistakes to Avoid

1. Do not call agent-sandbox API an "isolation API" — isolation comes from kernel primitives
2. Do not mention Kagenti as current or future — it has been absorbed into OpenShell
3. Do not use "Praxis" externally — always "Red Hat AI gateway"
4. Do not say "Red Hat OpenShell" — it is "NVIDIA OpenShell" (Red Hat is a contributor)
5. Do not confuse OpenShift AI (the product) with OpenShift Sandboxed Containers (different operator)
6. Do not call AutoRAG "production-ready" — it is Technology Preview
