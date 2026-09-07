# Red Hat AI — Platform, GPU Operations, and Hybrid Cloud

## Overview

Red Hat AI provides a platform to consistently build, deploy, and manage AI models and agentic applications at scale across the hybrid cloud. It treats GPUs as a shared utility and enables sovereign, disconnected, and multi-cloud deployments.

## GPU Operations and Governance

### The Problem with Traditional GPU Management
- High cost, low utilization
- GPU queue bottleneck (teams waiting for access)
- Shadow IT risks (teams procuring own GPUs)
- Fragmented infrastructure across teams

### Red Hat AI GPU Management Solution

**Consolidate and Simplify:**
- Pool GPUs cluster-wide as a shared IT utility
- Maximize cross-team usage and reduce hardware costs

**Intelligent Orchestration:**
- Dynamically scale and slice GPUs using Kueue and InstaSlice
- Request prioritization routing
- Inference-aware autoscaling (scales on KV cache pressure)

**Self-Service with Control:**
- On-demand compute for teams
- Enforce token quotas and rate limits
- Chargeback tracking for cost allocation

**Hybrid and Open Choice:**
- Day-0 support for diverse, next-gen AI accelerators
- NVIDIA (Blackwell, Vera Rubin), AMD (MI350X, MI355X), Intel (Xeon), IBM (Spyre), Google (TPU), AWS (Inferentia)

## Multi-Tenancy and Governance

Red Hat AI Enterprise provides:
- Multi-tenancy with strict isolation between teams
- Governed AI consumption with quotas and policies
- Model provenance and validation tracking
- AI Hub for platform-wide management
- Workbenches for data scientist self-service

## Hybrid Cloud Deployment

### Supported Environments

| Environment | Description |
|-------------|-------------|
| Edge | Lightweight inference at the network edge |
| Physical (Bare Metal) | Maximum performance for training and large-scale inference |
| Virtual | Existing virtualized infrastructure |
| Private Cloud | On-premises OpenShift deployments |
| Public Cloud | AWS, Azure, GCP with marketplace billing |
| Sovereign Cloud | In-country, regulated deployments |

### Disconnected / Air-Gapped Support

Red Hat AI fully supports air-gapped deployments:
- Mirror container images to internal registry
- Offline model catalog
- No external network dependencies at runtime
- Critical for defense, government, and regulated industries

### Cloud Marketplace Availability

Red Hat AI Enterprise is available on:
- AWS Marketplace (burn down MACC/EDP committed spend)
- Azure Marketplace
- Google Cloud Marketplace

Benefits:
- Use existing cloud committed spend for AI infrastructure
- Native line item on cloud bill
- No complex metering agents — trust-based node pricing
- Hourly + annual subscription options

## Red Hat AI Enterprise vs. OpenShift AI

| Product | Scope | Target |
|---------|-------|--------|
| **Red Hat AI Enterprise** | Full AI platform: inference + data + agents + platform + security | Organizations wanting complete AI stack |
| **Red Hat OpenShift AI** | MLOps/LLMOps platform on existing OpenShift | Teams already on OpenShift adding AI capabilities |
| **Red Hat AI Inference** | vLLM-based inference runtime only | Teams needing model serving without full platform |
| **Red Hat Enterprise Linux AI** | Single-server LLM inference appliance | Edge/individual server deployments |

## Red Hat AI Enterprise Capabilities

| Category | Features |
|----------|----------|
| AI Application Development | Workbenches, pipelines, model tuning, RAG |
| Model and Agent Catalog | Curated, validated models and MCP servers |
| Inference at Scale | vLLM, llm-d, AI Gateway |
| Security and Governance | Guardrails, red teaming, supply chain verification |
| Observability | MLflow tracing, model monitoring, drift detection |
| GPU Ops | Kueue, InstaSlice, chargeback, quotas |

## Key Value Propositions

1. **Scale AI efficiently:** Run any model and agent cost-efficiently at scale with an open, modular stack
2. **End-to-end governance:** Verifiable control over platform, models, and outputs with transparency
3. **Operate AI anywhere:** Unified, vendor-agnostic foundation across all environments
4. **Open source flexibility:** Access to cutting-edge innovations, reduce vendor lock-in
5. **Partner ecosystem:** Hardware vendors, SIs, cloud providers, ISVs

## Red Hat AI Services

| Service | Description | Duration |
|---------|-------------|----------|
| **AI Incubator** | Residency-style consulting to prototype and deploy custom AI solutions | 4-8 weeks |
| **AI Platform Foundation** | Deploy, validate, and operationalize the AI platform | Varies |
| **AI Assessment / Discovery** | Capture AI use cases, analyze architecture, propose roadmap | 1-2 weeks |
| **AI TAM** | Dedicated Technical Account Manager for ongoing AI guidance | Annual |
| **Training** | AI267, AI296, AI500, AI501 courses + certifications (EX267) | Self-paced or instructor-led |

### AI Incubator Details
- Residency-style engagement with Red Hat consultants
- Prototype a custom AI solution backed by customer data
- Strong focus on automation and production concerns
- Help release solution in customer environment
- Demonstrate MLOps best practices and patterns
- Upskill customer associates for continued development

## Customer Evidence

| Customer | Industry | Result |
|----------|----------|--------|
| BNP Paribas | Financial Services | $600M additional value from AI across 1,000 use cases; 900M+ tokens/day |
| Telenor | Telco | Norway's first sovereign AI cloud; localized language models |
| Verizon | Telco | Multimillion-dollar OpEx savings from accelerated inference |
| Airbus Helicopters | Manufacturing | Eliminated shadow IT; production-grade AI on bare metal |
| ARSAT | Telco | 30% reduction in operational costs; automated triage |
| DenizBank | Financial Services | Model dev environment from 1 week to 10 minutes |
| Clalit Health | Healthcare | AI apps from request to production in 2 weeks |
| City of Vienna | Government | Process time from 15 minutes to 5 seconds |
| Turkish Airlines | Aviation | 0.2% fuel efficiency improvement (significant savings) |

## Applicability to RFP Responses

When a customer asks about AI platform capabilities, GPU management, hybrid cloud AI, or product comparison, reference this document for:
- GPU pooling, scheduling, and chargeback
- Multi-cloud and sovereign deployment options
- Product portfolio positioning (Enterprise vs. OpenShift AI vs. RHEL AI)
- Services and engagement models
- Customer evidence and business outcomes
- Marketplace and commercial flexibility
