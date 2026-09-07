# 05 — Architecture Decision Records

> Key decisions that shape the enterprise evolution of rhoai-copilot.
> Format: Title, Status, Context, Decision, Consequences.
> Last updated: 2026-08-22

---

## ADR-001: Context Persistence via Markdown Files

**Status:** Accepted

**Context:**
AI coding agents operate within finite context windows. When working on a large codebase across multiple sessions, accumulated knowledge is lost at each context reset. This creates repeated exploration work, inconsistent decisions, and loss of strategic continuity.

**Decision:**
Maintain a `_context/` directory of structured Markdown files as the agent's persistent memory. Files are numbered 00-07 covering: codebase map, product assessment, persona JTBD, skill coverage, gap analysis, ADRs, roadmap, and exploration log. Any agent (human or AI) can resume from these files.

**Consequences:**
- (+) Knowledge survives context window resets
- (+) Multiple agents can collaborate via shared context files
- (+) Files are version-controlled alongside code
- (+) Human-readable format enables review and correction
- (-) Files can become stale if not maintained during code changes
- (-) Adds maintenance burden to keep context files synchronized with reality
- (-) Risk of context files diverging from actual codebase state

**Mitigation:** `07-EXPLORATION-LOG.md` tracks what was last verified and when. CI could validate key facts (skill count, file existence) against context files.

---

## ADR-002: Eval-First Skill Development

**Status:** Proposed

**Context:**
The repo has 22 skills but only 3 eval scenarios (14% coverage). Skills without eval scenarios cannot be regression-tested, and there is no way to measure if agent behavior degrades after changes. The `make eval` target is a stub.

**Decision:**
Adopt an eval-first development policy: every new skill MUST ship with at least one eval scenario. Every PR adding a skill must include a corresponding `eval/scenarios/<skill-name>.yaml` file. The skill PR template should include an eval scenario checklist item.

**Consequences:**
- (+) Every skill is testable from day one
- (+) Prevents the current 14% coverage gap from growing
- (+) Forces skill authors to think about expected behavior and safety constraints
- (+) Enables automated regression testing once the eval runner is built
- (-) Increases the overhead of skill development
- (-) Requires building the eval runner (GAP-001) to be useful beyond documentation

**Implementation:**
1. Update `skills/SKILL_SPEC.md` to add "Eval Scenario" as a required companion artifact
2. Update `.github/ISSUE_TEMPLATE/new-skill.md` to include eval scenario checklist
3. Add validation check in `make validate` to verify each skill has a corresponding eval scenario
4. Create `eval/scenarios/_template.yaml` for consistency

---

## ADR-003: Model-Agnostic Configuration Pattern

**Status:** Proposed

**Context:**
The agent currently uses Gemini 2.5 Flash exclusively via an OpenAI-compatible endpoint. Enterprise customers have diverse model requirements: some mandate IBM Granite for Red Hat alignment, others use GPT-4 or Claude, and air-gapped environments need locally-hosted models (vLLM, Ollama).

**Decision:**
Leverage the existing OpenAI-compatible `base_url` pattern in `config.yaml` as the model abstraction layer. Document configurations for multiple providers. Do not build a custom abstraction — rely on OpenAI API compatibility that most providers support.

**Provider configurations to document:**

```yaml
# Gemini (current default)
model:
  default: "gemini-2.5-flash"
  base_url: "https://generativelanguage.googleapis.com/v1beta/openai/"
  provider: custom
  api_key: "${GEMINI_API_KEY}"

# IBM Granite (Red Hat aligned)
model:
  default: "granite-3.3-8b-instruct"
  base_url: "https://api.watsonx.ai/v1/"
  provider: custom
  api_key: "${WATSONX_API_KEY}"

# Local vLLM (disconnected/air-gapped)
model:
  default: "granite-3.3-8b-instruct"
  base_url: "http://vllm.ai-models.svc:8000/v1/"
  provider: custom
  api_key: "dummy"

# OpenAI GPT-4
model:
  default: "gpt-4o"
  base_url: "https://api.openai.com/v1/"
  provider: custom
  api_key: "${OPENAI_API_KEY}"
```

**Consequences:**
- (+) No code changes needed — configuration only
- (+) Works for disconnected environments (local vLLM)
- (+) Aligns with Red Hat strategy (Granite models)
- (+) Customers choose their own model
- (-) Skills may behave differently across models (varying instruction-following quality)
- (-) No per-skill model routing (all skills use the same model)
- (-) Eval must cover multiple model providers to ensure consistent behavior

**Mitigation:** Add multi-model eval as part of GAP-001. Document known model-specific quirks.

---

## ADR-004: Observability via OpenTelemetry Sidecar vs In-Agent Instrumentation

**Status:** Proposed (Pending Decision)

**Context:**
The agent needs observability (metrics, traces, structured logs) for enterprise operations. Two approaches are viable:

**Option A: In-Agent Instrumentation**
- Add OpenTelemetry SDK to Hermes dependencies
- Instrument MCP tool calls with spans
- Export metrics via Prometheus endpoint
- Ship structured logs to stdout

**Option B: OTel Collector Sidecar**
- Deploy OTel Collector as sidecar container in agent pod
- Agent outputs unstructured logs/spans to localhost
- Collector processes, enriches, and exports to backends
- Agent code changes are minimal

**Decision:** PENDING — needs evaluation of Hermes SDK capabilities.

**Recommendation:** Option A (In-Agent) if Hermes supports plugin hooks for tool call interception. Option B (Sidecar) if Hermes is opaque. Hybrid approach (basic metrics in-agent + collector for log processing) is also viable.

**Consequences of each:**
- Option A: (+) lower latency, tighter integration, (-) coupled to agent code
- Option B: (+) decoupled, standard pattern, (-) higher resource usage, network hop

---

## ADR-005: Multi-Tenancy via Namespace Isolation vs Single-Agent Multi-Scope

**Status:** Proposed (Pending Decision)

**Context:**
Enterprise environments have multiple teams using RHOAI. The agent currently operates as a single instance with cluster-reader access. Two multi-tenancy models are viable:

**Option A: Namespace Isolation (One Agent Per Team)**
- Deploy separate agent instances per team/namespace
- Each agent has scoped RBAC (own namespace only)
- Independent config, skills, and memory
- Higher resource cost, simpler isolation

**Option B: Single Agent, Multi-Scope**
- One agent instance serves all teams
- User identity determines scope (namespace restrictions)
- Shared skills and memory, scoped data access
- Lower resource cost, complex access control

**Decision:** PENDING — depends on enterprise customer requirements and Hermes session model.

**Recommendation:** Start with Option A (simpler isolation model) for initial enterprise deployments. Evaluate Option B for large-scale deployments where resource efficiency matters.

**Key factors:**
- Hermes session model (does it support user-scoped contexts?)
- Compliance requirements (data isolation between teams)
- Resource constraints (agent pods per team may be expensive)
- Operational overhead (managing N agent instances vs 1)

---

## ADR-006: Workflow Execution Engine Selection

**Status:** Proposed (Pending Decision)

**Context:**
Three workflow YAML files define multi-step procedures (daily health, drift detection, incident response). These YAMLs are NOT directly executable — they serve as documentation. Actual execution uses Hermes cron prompts that invoke skills. This creates a gap between declared workflows and actual behavior.

**Options:**

**Option A: Hermes-Native (Current Pattern, Enhanced)**
- Convert workflow YAML into Hermes cron job configurations
- Each workflow becomes a Hermes cron prompt that chains skill invocations
- Pro: no new infrastructure. Con: workflow YAML is redundant documentation

**Option B: Lightweight Python Executor**
- Build a Python script that reads workflow YAML and orchestrates skill execution via Hermes API
- Supports conditions, inline steps, escalation hooks
- Pro: workflow YAML becomes the source of truth. Con: new component to maintain

**Option C: External Orchestrator (Argo Workflows, Tekton)**
- Use Kubernetes-native workflow engine
- Each step invokes Hermes via API call
- Pro: enterprise-grade, scalable, auditable. Con: heavy dependency, complex

**Decision:** PENDING — evaluate Hermes cron capabilities first.

**Recommendation:** Option A for Horizon 1 (formalize Hermes cron commands to match YAML). Option B for Horizon 2 (if conditions and inline steps are needed). Option C only if enterprise customer specifically requires K8s-native orchestration.

---

## ADR-007: Disconnected Environment Strategy

**Status:** Accepted (Existing Pattern, Needs Completion)

**Context:**
Disconnected/air-gapped environments are a primary design constraint (stated in AGENTS.md). The current implementation has partial support: skills handle disconnected scenarios, agent config disables web search, MCP servers are in-cluster. However, several referenced artifacts don't exist (overlays, profiles) and the Containerfile installs npm packages at build time.

**Decision:**
Complete the disconnected strategy by:
1. Creating the referenced `runtimes/hermes/overlays/disconnected/` Kustomize overlay
2. Creating `agent/profiles/connected.env` and `disconnected.env`
3. Vendoring all npm dependencies into the container image at build time
4. Providing an ImageSetConfiguration template for oc-mirror
5. Testing the full disconnected deploy flow end-to-end

**Consequences:**
- (+) Eliminates phantom path references in docs
- (+) Provides tested, production-ready disconnected deployment
- (+) npm dependencies available offline (already built into image, but documented)
- (-) Maintenance burden of separate overlays and profiles
- (-) Need to keep ImageSetConfiguration templates in sync with image references

---

## ADR Index

| ADR | Title | Status | Impact |
|-----|-------|--------|--------|
| 001 | Context persistence via `_context/` markdown files | Accepted | Process |
| 002 | Eval-first skill development | Proposed | Quality |
| 003 | Model-agnostic configuration pattern | Proposed | Architecture |
| 004 | Observability approach | Pending Decision | Operations |
| 005 | Multi-tenancy model | Pending Decision | Architecture |
| 006 | Workflow execution engine | Pending Decision | Architecture |
| 007 | Disconnected environment strategy | Accepted (needs completion) | Architecture |
