# 04 — Enterprise Gap Analysis

> Enterprise requirements vs current state, scored using RICE framework.
> RICE = (Reach x Impact x Confidence) / Effort
> Categorized using MoSCoW: Must / Should / Could / Won't (this cycle).
> Last updated: 2026-08-22

---

## Scoring Legend

**Reach (R):** How many personas/users benefit? (1-5)
**Impact (I):** How much does it move enterprise readiness? (1-5, where 5=blocker)
**Confidence (C):** How sure are we this is the right investment? (0.5-1.0)
**Effort (E):** Person-weeks to implement (1=trivial, 10=major)
**RICE Score:** (R x I x C) / E — higher = higher priority

---

## P0 — Must Have (Enterprise Blockers)

These gaps would prevent enterprise adoption or cause compliance failures.

### GAP-001: Evaluation Framework Buildout

| Dimension | Value |
|-----------|-------|
| **Current State** | 3 eval scenarios covering 2 personas and 3 of 22 skills. `make eval` is a stub that counts files. No automated runner, no CI integration, no golden transcripts. |
| **Target State** | Minimum 1 eval scenario per skill (22+), automated runner, CI gate, golden transcripts for regression testing, adversarial safety scenarios. |
| **Reach** | 5 — all personas benefit from reliable agent behavior |
| **Impact** | 5 — no enterprise buyer accepts untested AI agent behavior |
| **Confidence** | 1.0 — universal requirement |
| **Effort** | 6 — build runner, write 19+ scenarios, CI integration |
| **RICE** | 4.2 |
| **MoSCoW** | MUST |

**Work Items:**
1. Build `make eval` automated runner (invoke LLM, compare against expected_tools/behavior, score via rubric)
2. Write eval scenarios for all 22 skills (minimum 1 each, 2+ for critical skills)
3. Add eval step to CI pipeline (validate.yaml or new workflow)
4. Create golden transcripts directory with expected tool call traces
5. Add adversarial scenarios testing safety boundary enforcement
6. Add eval scenarios for all 5 personas (currently 0 for DataSci, MLOps, AIEng)

---

### GAP-002: Audit / Compliance Logging

| Dimension | Value |
|-----------|-------|
| **Current State** | No audit trail. Agent actions are not logged to any persistent store. Tier 2 confirmations are conversational only with no record. |
| **Target State** | Immutable audit log of every agent action (tool calls, user confirmations, write operations) in structured JSON. Optional forwarding to enterprise SIEM/log aggregator. |
| **Reach** | 5 — required for any regulated environment |
| **Impact** | 5 — compliance blocker (SOC2, FedRAMP, HIPAA) |
| **Confidence** | 1.0 — non-negotiable for enterprise |
| **Effort** | 4 — structured logging + PVC storage + optional forwarding |
| **RICE** | 6.25 |
| **MoSCoW** | MUST |

**Work Items:**
1. Define audit event schema (timestamp, user, action, tool, parameters, result, tier, confirmation)
2. Implement structured JSON logging in Hermes entrypoint or agent wrapper
3. Store audit logs on PVC (separate from agent state)
4. Add log rotation and retention policy
5. Document integration with enterprise log aggregators (Splunk, ELK, CloudWatch)
6. Create audit report generation skill

---

### GAP-003: Release Engineering

| Dimension | Value |
|-----------|-------|
| **Current State** | No semver. CHANGELOG.md has only "Unreleased" section. Image tagged `latest` only. No release process. No compatibility matrix. |
| **Target State** | Semantic versioning, automated CHANGELOG, versioned container images, GitHub Releases, compatibility matrix (agent version x RHOAI version x OCP version). |
| **Reach** | 5 — all operators need predictable upgrades |
| **Impact** | 4 — blocks upgrade confidence and fleet management |
| **Confidence** | 1.0 — standard engineering practice |
| **Effort** | 3 — CI automation + docs |
| **RICE** | 6.67 |
| **MoSCoW** | MUST |

**Work Items:**
1. Adopt semver (v0.x.y initially, v1.0.0 at enterprise GA)
2. Automate CHANGELOG generation from conventional commits
3. Tag container images with version + git SHA (not just `latest`)
4. Create GitHub Release workflow triggered by version tags
5. Document compatibility matrix in README or docs/reference/
6. Create upgrade path documentation

---

### GAP-004: Documentation Fixes

| Dimension | Value |
|-----------|-------|
| **Current State** | Broken cross-links (disconnected-setup.md path wrong in 3 locations). Stale skill count (19 vs 22). Phantom paths referenced (agent/profiles/, overlays/disconnected/). ArgoCD credential docs conflict. |
| **Target State** | All links valid, all counts accurate, all referenced paths exist or are removed. |
| **Reach** | 5 — every user reads docs |
| **Impact** | 3 — credibility issue but not a functional blocker |
| **Confidence** | 1.0 — clearly broken |
| **Effort** | 1 — straightforward fixes |
| **RICE** | 15.0 |
| **MoSCoW** | MUST |

**Work Items:**
1. Fix disconnected-setup.md link in README.md (points to `docs/getting-started/` instead of `docs/guides/`)
2. Fix disconnected-setup.md link in troubleshooting.md
3. Fix disconnected-setup.md link in deployment-guide.md
4. Update skill count in architecture.md from 19 to 22
5. Either create `agent/profiles/` and `runtimes/hermes/overlays/disconnected/` or remove references
6. Resolve ArgoCD credential conflict (ConfigMap vs CR) — standardize on CR approach
7. Standardize ARGOCD_BASE_URL source documentation

---

### GAP-005: Security Hardening

| Dimension | Value |
|-----------|-------|
| **Current State** | Non-root container, dropped capabilities, cluster-reader RBAC, secrets in OpenShift Secret. No NetworkPolicy, no PodSecurity, no mTLS, no image signing, no vuln scanning. |
| **Target State** | NetworkPolicy for agent + MCP pods, PodSecurity restricted profile, mTLS between agent and HTTP MCPs, image signing with cosign, SBOM generation, vuln scanning in CI. |
| **Reach** | 4 — security team requirement for production |
| **Impact** | 4 — security audit blocker |
| **Confidence** | 0.9 — well-understood practices |
| **Effort** | 5 — multiple manifests + CI changes |
| **RICE** | 2.88 |
| **MoSCoW** | MUST |

**Work Items:**
1. Add NetworkPolicy for rhoai-copilot namespace (agent pod ingress/egress)
2. Add NetworkPolicy for each MCP server namespace
3. Add PodSecurity restricted profile labels to namespaces
4. Add cosign image signing step to build-image.yaml
5. Add Trivy/Grype vulnerability scanning to CI
6. Generate SBOM with syft in build pipeline
7. Document secret rotation procedures
8. Document security hardening guide in docs/guides/

---

## P1 — Should Have (High-Value Enhancements)

These significantly increase the agent's value proposition and address the largest persona gaps.

### GAP-006: Train / Evaluate / Maintain-Safety Skills

| Dimension | Value |
|-----------|-------|
| **Current State** | 3 lifecycle phases have 0 skills (only placeholder READMEs). 9 planned skills named but not built. Data Scientist persona is most underserved. |
| **Target State** | Minimum 2 skills per phase (6 total) covering the highest-impact jobs: distributed training, model benchmarking, guardrails validation. |
| **Reach** | 4 — DataSci, MLOps, AIEng personas |
| **Impact** | 4 — completes the lifecycle story |
| **Confidence** | 0.8 — skills well-scoped in READMEs |
| **Effort** | 8 — 6 skills + eval scenarios + kustomization updates |
| **RICE** | 1.6 |
| **MoSCoW** | SHOULD |

**Work Items:**
1. Build `train/distributed-training-setup` — Ray/PyTorchJob/KueueJob configuration
2. Build `train/training-job-monitor` — training progress tracking and failure diagnosis
3. Build `evaluate/model-benchmarker` — LM-Eval integration for model quality assessment
4. Build `evaluate/bias-detector` — fairness analysis across demographic dimensions
5. Build `maintain-safety/guardrails-validator` — content filtering and PII detection config
6. Build `maintain-safety/compliance-checker` — model card and regulatory compliance validation
7. Add eval scenarios for each new skill
8. Update kustomization.yaml with new skill ConfigMaps
9. Update Hermes entrypoint to mount new skills

---

### GAP-007: Observability Stack

| Dimension | Value |
|-----------|-------|
| **Current State** | Hermes dashboard with basic auth. No metrics, no tracing, no structured logging, no cost tracking. |
| **Target State** | OpenTelemetry instrumentation, Prometheus metrics endpoint, structured JSON logging, token usage and cost tracking. |
| **Reach** | 4 — SRE and platform eng |
| **Impact** | 4 — ops team cannot manage what they cannot measure |
| **Confidence** | 0.8 — standard patterns exist |
| **Effort** | 6 — OTel integration + metrics + dashboards |
| **RICE** | 2.13 |
| **MoSCoW** | SHOULD |

**Work Items:**
1. Add OpenTelemetry SDK to Containerfile dependencies
2. Instrument MCP tool calls with spans (tool name, latency, status)
3. Expose Prometheus metrics endpoint (/metrics on separate port)
4. Define key metrics: tool_call_duration, tool_call_errors, llm_tokens_used, active_sessions
5. Create ServiceMonitor for OpenShift monitoring stack
6. Add Grafana dashboard template
7. Implement structured JSON logging with correlation IDs
8. Add token usage tracking and cost estimation

---

### GAP-008: Alerting Integrations

| Dimension | Value |
|-----------|-------|
| **Current State** | Workflow escalation hooks defined (alert-channel, create-github-issue, notify-oncall) but not wired to any actual alerting system. |
| **Target State** | Slack, PagerDuty, and/or Microsoft Teams integration for Tier 3 workflow escalations and critical alerts. |
| **Reach** | 3 — SRE persona primarily |
| **Impact** | 3 — escalations are meaningless without delivery |
| **Confidence** | 0.9 — well-defined integration patterns |
| **Effort** | 3 — webhook/API integrations |
| **RICE** | 2.7 |
| **MoSCoW** | SHOULD |

**Work Items:**
1. Build `monitor/alerting-integration` skill or add to agent config
2. Implement Slack webhook integration for workflow escalations
3. Implement PagerDuty Events API integration for incident-response workflow
4. Add alerting configuration section to config.yaml
5. Document alerting setup in docs/guides/

---

### GAP-009: Multi-Model Provider Support

| Dimension | Value |
|-----------|-------|
| **Current State** | Gemini 2.5 Flash only (via OpenAI-compatible API). Single provider, single model. |
| **Target State** | Model abstraction supporting Gemini, GPT-4, Claude, IBM Granite, local vLLM/Ollama. Configurable per-skill or per-session. |
| **Reach** | 5 — enterprise customers have diverse model policies |
| **Impact** | 3 — model lock-in is a procurement risk |
| **Confidence** | 0.8 — Hermes supports provider switching |
| **Effort** | 4 — config patterns + testing + docs |
| **RICE** | 3.0 |
| **MoSCoW** | SHOULD |

**Work Items:**
1. Document model provider abstraction in config.yaml (already uses OpenAI-compatible base_url)
2. Add example configs for GPT-4, Claude, Granite, local vLLM
3. Test all skills with at least 2 different model providers
4. Add model selection guide to docs
5. Consider per-skill model override capability

---

### GAP-010: Workflow Engine Formalization

| Dimension | Value |
|-----------|-------|
| **Current State** | 3 workflow YAML files define procedures but no engine reads them. Execution is via Hermes cron prompts that reference skills. YAML is documentation, not executable. |
| **Target State** | Either (a) Hermes cron natively interprets workflow YAML or (b) a lightweight engine translates YAML → Hermes cron commands. Support conditions, inline steps, escalation hooks. |
| **Reach** | 3 — SRE and platform eng |
| **Impact** | 3 — workflows are the Tier 3 autonomy path |
| **Confidence** | 0.6 — depends on Hermes capabilities |
| **Effort** | 6 — engine design + implementation + testing |
| **RICE** | 0.9 |
| **MoSCoW** | SHOULD |

**Work Items:**
1. Evaluate whether Hermes SDK supports workflow YAML parsing
2. If not, build lightweight workflow executor (Python script reading YAML, invoking skills via Hermes API)
3. Implement conditional step execution (incident-response disconnected check)
4. Implement inline reasoning steps (drift-detection classify)
5. Implement escalation hooks (GitHub issue creation, webhook calls)
6. Add workflow execution logging and status tracking

---

## P2 — Could Have (Future Enhancements)

### GAP-011: Multi-Tenancy

| Dimension | Value |
|-----------|-------|
| **Current State** | Single-tenant, one agent instance per cluster |
| **RICE** | 0.8 |
| **MoSCoW** | COULD |

Namespace-scoped agent instances per team, tenant-aware data isolation, usage quotas. High effort (8+ weeks), moderate reach.

### GAP-012: Skill Marketplace / Registry

| Dimension | Value |
|-----------|-------|
| **Current State** | Skills are ConfigMaps in a single repo |
| **RICE** | 0.6 |
| **MoSCoW** | COULD |

Community skill publishing, discovery, installation. Requires versioning, dependency resolution, trust model. Nice-to-have for ecosystem growth.

### GAP-013: LangGraph / CrewAI Runtimes

| Dimension | Value |
|-----------|-------|
| **Current State** | README stubs only |
| **RICE** | 0.5 |
| **MoSCoW** | COULD |

Runtime choice for teams preferring LangChain or CrewAI patterns. Requires skill adapter layer. Low priority unless customer demand.

### GAP-014: Golden Transcript Library

| Dimension | Value |
|-----------|-------|
| **Current State** | No expected interaction transcripts |
| **RICE** | 1.5 |
| **MoSCoW** | COULD |

Expected tool call sequences + agent responses for regression testing. Feeds into GAP-001 eval framework. Could be built incrementally as eval scenarios are created.

### GAP-015: Interactive Onboarding

| Dimension | Value |
|-----------|-------|
| **Current State** | Examples are narrative READMEs |
| **RICE** | 0.75 |
| **MoSCoW** | COULD |

Guided first-run experience per persona. Agent detects new user, walks through persona selection and demo interaction. Nice-to-have for adoption.

---

## RICE Priority Stack Rank

| Rank | Gap | RICE | MoSCoW | Effort (wks) |
|-----:|-----|-----:|--------|-------------:|
| 1 | GAP-004: Doc Fixes | 15.0 | MUST | 1 |
| 2 | GAP-003: Release Engineering | 6.67 | MUST | 3 |
| 3 | GAP-002: Audit Logging | 6.25 | MUST | 4 |
| 4 | GAP-001: Eval Framework | 4.2 | MUST | 6 |
| 5 | GAP-009: Multi-Model Support | 3.0 | SHOULD | 4 |
| 6 | GAP-005: Security Hardening | 2.88 | MUST | 5 |
| 7 | GAP-008: Alerting Integration | 2.7 | SHOULD | 3 |
| 8 | GAP-007: Observability | 2.13 | SHOULD | 6 |
| 9 | GAP-006: Missing Skills | 1.6 | SHOULD | 8 |
| 10 | GAP-014: Golden Transcripts | 1.5 | COULD | 3 |
| 11 | GAP-010: Workflow Engine | 0.9 | SHOULD | 6 |
| 12 | GAP-011: Multi-Tenancy | 0.8 | COULD | 8 |
| 13 | GAP-015: Onboarding | 0.75 | COULD | 4 |
| 14 | GAP-012: Skill Marketplace | 0.6 | COULD | 8 |
| 15 | GAP-013: Alt Runtimes | 0.5 | COULD | 8 |

---

## Dependency Graph

```
GAP-004 (Doc Fixes) ─────────── standalone, no deps
GAP-003 (Release Eng) ────────── standalone
GAP-002 (Audit) ──────────────── standalone
GAP-001 (Eval) ───────────────── depends on: GAP-014 (optional)
GAP-005 (Security) ──────────── standalone
GAP-009 (Multi-Model) ────────── standalone
GAP-008 (Alerting) ──────────── depends on: GAP-010 (workflow engine for escalation hooks)
GAP-007 (Observability) ──────── standalone
GAP-006 (Missing Skills) ──────── depends on: GAP-001 (every skill needs eval)
GAP-010 (Workflow Engine) ────── standalone
GAP-011 (Multi-Tenancy) ──────── depends on: GAP-002 (audit), GAP-005 (security)
```
