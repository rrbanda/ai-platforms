# AI Safety Stack — Red Teaming & Guardrails with Red Hat AI

## Overview

Red Hat AI provides an integrated safety stack for enterprise AI deployments on OpenShift AI. The stack combines pre-production adversarial testing (Garak), runtime guardrails (NeMo Guardrails via TrustyAI), and continuous safety monitoring to ensure AI systems are secure against prompt injection, jailbreaks, data leakage, and model abuse.

## Red Hat's AI Safety Principle

Security and safety capabilities cannot be bolted on after deployment — they must be integrated throughout the AI lifecycle, from data generation to continuous monitoring in production.

## Component Architecture

| Layer | Component | Function |
|-------|-----------|----------|
| **Pre-production testing** | Garak (NVIDIA) | Automated adversarial vulnerability scanner for LLMs |
| **Runtime protection** | NeMo Guardrails (NVIDIA) | Programmable input/output filtering at inference boundary |
| **Orchestration** | TrustyAI Guardrails Orchestrator | Screens model inputs and outputs for safety policy enforcement |
| **Operations** | TrustyAI Operator | Manages deployment of guardrails via Custom Resource Definitions |

## Garak — The "Nmap for LLMs"

Garak (Generative AI Red-teaming and Assessment Kit) is an open-source LLM vulnerability scanner with 120+ adversarial probes.

### Probe Categories

- **Prompt Injection**: Tests for direct and indirect injection attacks
- **Jailbreaks**: DAN, encoding attacks, role-play exploits
- **Data Leakage**: Training data extraction, PII exposure
- **Latent Injection**: Hidden instructions in tool responses
- **Model Abuse**: Attempts to use models for harmful purposes

### Architecture

1. **Generators**: Wraps the target LLM (OpenAI, HuggingFace, vLLM) to handle API calls
2. **Probes**: Generates adversarial prompts to exploit weaknesses
3. **Detectors**: Analyzes outputs to determine if attacks succeeded
4. **Evaluators**: Converts detector results into pass/fail metrics
5. **Harnesses**: Orchestrates the entire testing workflow

### Integration with OpenShift AI

- Run systematic red-teaming workflows through Kubeflow Pipelines
- Automated vulnerability scanning as part of model deployment pipeline
- Results feed into model registry for governance tracking
- Scans based on OWASP Top 10 for LLM Applications taxonomy

### Enterprise Enhancement (Chatterbox Labs)

Red Hat's acquisition of Chatterbox Labs (December 2025) added:
- Enterprise-grade automated red teaming
- Specifically measures how agents respond to adversarial inputs
- Detects when MCP server actions are triggered by injected instructions
- Quantitative safety scoring for compliance reporting

## NeMo Guardrails — Runtime Protection

NeMo Guardrails provides programmable conversational rails at the inference boundary:

### Deployment

- Deployed via Custom Resource Definition (CRD) managed by TrustyAI Operator
- Runs as a service in front of vLLM model serving
- Applies regardless of which framework makes the call (LangChain, CrewAI, custom)

### API Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/v1/guardrail/checks` | Validate messages against guardrails without generating LLM response |
| `/v1/chat/completions` | Process chat completions with guardrail enforcement |

### Built-in Guardrail Types

| Type | Function |
|------|----------|
| **Injection Detection** | Detect prompt injection attacks in user input |
| **Content Filtering** | Block unsafe, harmful, or off-topic content |
| **Sensitive Data Detection** | Prevent PII/PHI/financial data exposure |
| **Topic Boundaries** | Keep conversations within approved scope |
| **Factual Constraints** | Enforce accuracy requirements |
| **Custom Validation** | Organization-specific rules |

### Request Flow

```
User Request → NeMo Guardrails Server → Internal Detectors (input check)
    → Forward to vLLM Model → External Detectors (output check)
    → Response returned to user (or blocked)
```

## Empirical Results

From Red Hat's published testing ("Testing infrastructure red teaming with abliterated models"):

- Sandbox isolation alone drops credential exfiltration from **67% success to zero**
- Layered guardrails + sandbox provides defense-in-depth against novel attacks
- NeMo Guardrails catches fabricated information before it reaches customers

## Applicability to Security Engagements

For RFPs requiring "AI Security Testing Support":

| Requirement | Red Hat Solution |
|-------------|-----------------|
| Prompt-injection testing | Garak probes (direct + indirect injection) |
| Model-abuse testing | Garak adversarial harness with 120+ probe types |
| Red-team exercises for GenAI | Automated red-teaming via Kubeflow Pipelines |
| Validation of remediation effectiveness | Before/after Garak scans with quantitative scoring |
| Runtime protection | NeMo Guardrails at inference boundary |
| Compliance evidence | Pass/fail metrics exportable for audit |

## Maturity Status

| Component | Status |
|-----------|--------|
| NeMo Guardrails (via TrustyAI) | Generally Available (RHOAI 3.4+) |
| TrustyAI Guardrails Orchestrator | Generally Available |
| Garak | Technology Preview (RHOAI 3.4+) |
| Automated red-teaming pipelines | Technology Preview |

## Source

Based on "Building trust through AI red teaming: Red Hat's approach to testing model safety" (Red Hat Blog, 2026), "Every layer counts: Defense in depth for AI agents with Red Hat AI" (Red Hat Developer, May 2026), Red Hat OpenShift AI 3.4 guardrails documentation, and Red Hat Summit 2026 TrustyAI session notes.
