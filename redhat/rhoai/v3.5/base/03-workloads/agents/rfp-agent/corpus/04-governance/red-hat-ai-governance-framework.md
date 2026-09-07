---
title: Red Hat AI Governance Framework
date: 2026-08-19
source: Red Hat AI platform documentation, defense-in-depth architecture, asago project
product_area: AI/ML, Governance, Security
---

# Red Hat AI Governance Framework

## Defense-in-Depth for AI: Six Layers

Layered security model for AI agent deployments on OpenShift.

| Layer | Function | Technology |
|-------|----------|-----------|
| 1. Infrastructure isolation | Hardware-level VM boundary per workload | OpenShift Sandboxed Containers (Kata Containers) |
| 2. Agent sandboxing | Process-level confinement within sandbox | OpenShell supervisor + process isolation |
| 3. Network segmentation | East-west traffic control between agents and services | OPA/Rego policies + Kubernetes NetworkPolicies |
| 4. Tool access control | Per-agent authorization for external tool invocation | MCP Gateway (Technology Preview) |
| 5. Runtime guardrails | Input/output filtering and content safety | NeMo Guardrails + TrustyAI Guardrails Orchestrator |
| 6. Observability | Identity-aware tracing and audit logging | SPIFFE/SPIRE identity + OpenTelemetry tracing + MLflow tracking |

### Layer 1: Infrastructure Isolation

- Each AI agent runs inside a dedicated Kata Containers micro-VM
- Hardware-enforced memory and CPU isolation
- Separate kernel per workload — kernel exploits contained
- Managed via OpenShift Sandboxed Containers operator
- RuntimeClass: `kata-remote` or `kata`

### Layer 2: Agent Sandboxing

- OpenShell supervisor intercepts all shell and filesystem operations
- Process isolation via seccomp + AppArmor/SELinux profiles
- Allowlist-based command execution
- File system access scoped to designated working directories
- Prevents lateral movement within the container

### Layer 3: Network Segmentation

- Kubernetes NetworkPolicies restrict pod-to-pod communication
- OPA/Rego policies enforce fine-grained authorization
- Default-deny ingress and egress per agent namespace
- Explicit allowlists for required service endpoints
- DNS-level filtering for external access

### Layer 4: Tool Access Control

- MCP Gateway (Technology Preview) mediates all tool calls
- Per-agent tool authorization policies
- Rate limiting and quota enforcement
- Audit logging of every tool invocation
- Token-scoped access to external APIs

### Layer 5: Runtime Guardrails

- NeMo Guardrails: Colang-based input/output filtering
- Topic control prevents off-topic responses
- TrustyAI Guardrails Orchestrator: coordinates multiple guardrail checks
- Hallucination reduction via fact-checking rails
- PII detection and redaction

### Layer 6: Observability

- SPIFFE/SPIRE: cryptographic workload identity for every agent
- OpenTelemetry: distributed tracing across agent interactions
- MLflow: experiment tracking, model versioning, metric logging
- Audit trail: every decision, tool call, and response logged with identity

---

## Pre-Production Testing

### Garak — LLM Vulnerability Scanner

| Capability | Detail |
|-----------|--------|
| Status | Technology Preview |
| Prompt injection | Tests resistance to injection attacks |
| Jailbreak probing | Evaluates guardrail bypass attempts |
| Data leakage | Detects training data extraction vectors |
| Extensibility | Plugin architecture for custom probes |

### EvalHub — Evaluation Orchestration

| Capability | Detail |
|-----------|--------|
| Frameworks supported | RAGAS, DeepEval, lm-evaluation-harness |
| Purpose | Automated quality and safety evaluation |
| Deployment | OpenShift job-based execution |
| Tracking | Results stored in MLflow |

### MLflow — Experiment Tracking

| Capability | Detail |
|-----------|--------|
| Experiment tracking | Compare model versions and configurations |
| Model registry | Version and stage models through lifecycle |
| Metric logging | Track accuracy, latency, safety scores |
| Artifact storage | Store evaluation datasets and results |

---

## Runtime Safety

### NeMo Guardrails

- Input filtering: block malicious, off-topic, or policy-violating prompts
- Output filtering: prevent harmful, non-compliant, or hallucinated responses
- Topic control: constrain model to approved subject domains
- Hallucination reduction: fact-checking against knowledge base
- Configuration: Colang policy language (declarative)

### TrustyAI

| Capability | Detail |
|-----------|--------|
| Bias detection | Evaluate model outputs for demographic bias |
| Explainability | LIME/SHAP explanations for model decisions |
| Fairness monitoring | Continuous fairness metric tracking |
| Drift tracking | Detect model performance degradation over time |
| Integration | Red Hat OpenShift AI (RHOAI) native |

---

## Policy Automation — asago

Automates translation of governance policies into operational infrastructure controls.

| Stage | Function |
|-------|----------|
| Risk mapping | Identify AI components, data flows, stakeholders |
| Risk assessment | Score against governance framework requirements |
| Risk mitigation | Generate guardrails, policies, access controls |
| Production deployment | Output as Kubernetes, Terraform, Ansible configurations |

### Framework Mapping

| Framework | Coverage |
|-----------|----------|
| NIST AI RMF | Govern, Map, Measure, Manage functions |
| EU AI Act | Risk classification + control generation |
| OWASP LLM Top 10 | All 10 vulnerability categories |

---

## Model Provenance

### InstructLab

- Transparent training data via published taxonomies
- Community-contributed skills and knowledge with attribution
- Synthetic data generation process documented
- Weekly model releases with changelog

### Granite Models

- Apache License 2.0
- Dataset transparency: training data sources published
- Model cards with performance benchmarks
- Reproducible training methodology

### SBOM for Models

- Software bill of materials tracking for AI models
- Includes: base model, fine-tuning data, dependency versions
- Enables supply chain verification for model artifacts

---

## Compliance Mapping

| Standard | Mechanism | Status |
|----------|-----------|--------|
| ISO 42001 (AI Management System) | Process alignment | In progress |
| NIST AI RMF | asago automation | Supported |
| EU AI Act | asago + TrustyAI | Supported |
| OWASP LLM Top 10 | Garak + NeMo Guardrails + asago | Supported |

---

## Deployment Patterns

### AutoRAG

- Automated RAG pipeline optimization
- Available in RHOAI 3.4+
- Evaluates chunking strategies, embedding models, retrieval parameters
- Outputs optimized pipeline configuration

### OGX (OpenShift GenAI eXchange)

- Agent-as-a-service for inference and embeddings
- Standardized API endpoints for model serving
- Multi-model routing and load balancing
- Integrated with RHOAI model serving

### Milvus

- Vector database for knowledge retrieval
- Deployed as managed service on OpenShift
- Supports billions of vectors with millisecond search
- Used by RAG pipelines for document retrieval
- Persistent storage via OpenShift PVCs
