# Red Hat AI — Agentic AI and AgentOps

## Overview

Red Hat AI provides an agile, stable foundation to accelerate the deployment and management of agentic AI workflows. It delivers enterprise-grade AgentOps for safely operationalizing agents with a framework-agnostic approach (Bring Your Own Agent).

## What is Agentic AI?

- **Gen AI** is the creator — generates output by following predefined rules
- **AI Agent** is the doer — executes tasks and makes decisions using planning, tools, reasoning, and execution
- **Agentic AI** is the orchestrator — enables multiple agents to collaborate and adapt to solve complex problems autonomously, adding memory and sub-agent coordination

## Red Hat AI Agent Capabilities

### Safety and Observability

**Agent Sandbox:**
- Zero-trust container and microVM isolation for each agent
- Every agent runs in its own isolated environment
- Prevents lateral movement and data exfiltration

**MLflow Tracing:**
- Every LLM call, tool use, and decision is logged
- Full audit trail for compliance and debugging
- Continuous scoring and drift detection via EvalHub

### Agent Identity and Security

**Cryptographic Identity (SPIFFE/SPIRE):**
- Short-lived, keyless identity for each agent
- No long-lived credentials to manage or rotate
- Standard-based workload identity

**MCP Gateway:**
- Per-tool authorization and audit
- Centralized authentication and access control
- Observability for all tool interactions
- Manages MCP servers as Kubernetes-native workloads

**Scoped OAuth2 Token Exchange:**
- Least-privilege access for each agent action
- Fine-grained permission boundaries

### Scalability and Performance

- **vLLM:** High-throughput model serving for agent reasoning
- **llm-d:** Dynamic inference routing for unpredictable agent workloads
- **Inference-aware autoscaling:** Scales on KV cache pressure, not just CPU/memory

## AgentOps — Operational Lifecycle

AgentOps is a unified approach for managing the full lifecycle, security, and performance of AI agents and their tools.

Components:
| Component | Function |
|-----------|----------|
| Observability | Trace agent steps, monitor performance |
| Tracing | Full decision audit trail |
| Evaluation | Continuous quality scoring |
| Safety/Security | Guardrails, sandbox, identity |
| Registry | Versioned agent and MCP server assets |
| Catalog | Discover and deploy trusted MCP servers |
| Lifecycle Management | Deploy, update, rollback agents as K8s workloads |
| Identity | Per-agent cryptographic identity |

## Enterprise MCP Management

A platform approach for governing AI agent access to enterprise tools and APIs:

- **Lifecycle Management:** Manages MCP servers as Kubernetes-native workloads
- **MCP Gateway:** Centralized authentication, access control, and observability
- **Catalog:** Teams discover and deploy trusted MCP servers from a curated registry

## Dedicated AI Experiences

Red Hat AI provides dedicated dashboard experiences:
- **AI Hub:** Platform engineering view for managing models, agents, and infrastructure
- **Gen AI Studio:** Developer-focused experience for building and tuning AI applications

## Key Differentiators

1. **Framework-agnostic:** Use any agent framework (LangChain, CrewAI, AutoGen, custom)
2. **Security-first:** Zero-trust isolation, cryptographic identity, per-tool authorization
3. **Kubernetes-native:** Agents and MCP servers managed as standard K8s workloads
4. **Observable:** Every agent action traced and auditable
5. **Scalable:** Inference-aware autoscaling handles unpredictable agent compute needs

## Applicability to RFP Responses

When a customer asks about deploying agents in production, governing AI tool access, or securing autonomous AI systems, reference this document for:
- Agent isolation and sandbox architecture
- MCP Gateway for tool governance
- Cryptographic agent identity (SPIFFE/SPIRE)
- AgentOps lifecycle management
- Observability and tracing requirements
- Enterprise MCP server catalog and registry
