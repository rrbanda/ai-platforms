# 06 — Prioritized Roadmap

> Three-horizon execution plan with MoSCoW categorization.
> Based on RICE-scored gap analysis (04-GAP-ANALYSIS.md) and persona JTBD (02-PERSONA-JTBD.md).
> Last updated: 2026-08-22

---

## Executive Summary

| Horizon | Theme | Timeline | Outcomes |
|---------|-------|----------|----------|
| H1 | Foundation Hardening | Weeks 1-4 | Trustworthy, testable, releasable |
| H2 | Capability Expansion | Weeks 5-12 | Full lifecycle, multi-model, observable |
| H3 | Enterprise Scale | Weeks 13-24 | Multi-tenant, extensible, ecosystem |

**Current maturity:** 2.0/5.0 (Early Production)
**H1 target:** 3.0/5.0 (Production-Ready)
**H2 target:** 3.8/5.0 (Enterprise-Capable)
**H3 target:** 4.5/5.0 (Enterprise-Grade)

---

## Horizon 1: Foundation Hardening (Weeks 1-4)

> Theme: "Make what exists trustworthy before adding more."
> Goal: Raise overall maturity from 2.0 to 3.0/5.0.
> MoSCoW: All items are MUST or high-priority SHOULD.

### Week 1: Quick Wins and Trust Fixes

| # | Work Item | Gap | Priority | Effort | Dimension Impact |
|---|-----------|-----|----------|--------|------------------|
| 1.1 | Fix all broken documentation links | GAP-004 | MUST | 2h | Documentation 2.5→3.5 |
| 1.2 | Update stale skill count (19→22) in architecture.md | GAP-004 | MUST | 15min | Documentation |
| 1.3 | Resolve ArgoCD credential doc conflict (standardize on CR) | GAP-004 | MUST | 1h | Documentation |
| 1.4 | Create `agent/profiles/connected.env` and `disconnected.env` or remove references | GAP-004/ADR-007 | MUST | 2h | Disconnected 2.5→3.0 |
| 1.5 | Create `_context/` knowledge base (this deliverable) | ADR-001 | MUST | 4h | Process |
| 1.6 | Adopt semver — tag v0.1.0, update CHANGELOG | GAP-003 | MUST | 2h | Release 1.0→2.0 |

**Week 1 deliverables:** Clean docs, versioned repo, context files established.

### Week 2: Release Engineering and CI

| # | Work Item | Gap | Priority | Effort | Dimension Impact |
|---|-----------|-----|----------|--------|------------------|
| 2.1 | Add version tagging to container images (`:v0.1.0` + `:sha-abc1234`) | GAP-003 | MUST | 4h | Release 2.0→3.0 |
| 2.2 | Create GitHub Release workflow (on tag push) | GAP-003 | MUST | 4h | Release |
| 2.3 | Create compatibility matrix doc (agent x RHOAI x OCP) | GAP-003 | MUST | 2h | Release 3.0→3.5 |
| 2.4 | Add eval scenario template (`eval/scenarios/_template.yaml`) | GAP-001 | MUST | 1h | Testing |
| 2.5 | Write eval scenarios for 5 highest-value skills | GAP-001 | MUST | 8h | Testing 1.0→1.5 |

Target skills for initial eval: `rhoai-platform-status`, `rhoai-install-validator`, `workbench-troubleshooter`, `incident-runbook`, `maas-deploy-model`.

**Week 2 deliverables:** Versioned releases, 8 total eval scenarios, release automation.

### Week 3: Security and Eval Foundation

| # | Work Item | Gap | Priority | Effort | Dimension Impact |
|---|-----------|-----|----------|--------|------------------|
| 3.1 | Add NetworkPolicy for rhoai-copilot namespace | GAP-005 | MUST | 4h | Security 2.0→2.5 |
| 3.2 | Add NetworkPolicy for MCP server namespaces | GAP-005 | MUST | 4h | Security |
| 3.3 | Add PodSecurity restricted labels | GAP-005 | MUST | 2h | Security 2.5→3.0 |
| 3.4 | Build `make eval` automated runner (MVP) | GAP-001 | MUST | 16h | Testing 1.5→2.5 |
| 3.5 | Write eval scenarios for 5 more skills | GAP-001 | MUST | 8h | Testing |

Target skills for second batch: `capacity-forecaster`, `serving-runtime-advisor`, `rhoai-dsc-inspector`, `daily-report-generator`, `model-promotion-workflow`.

**Week 3 deliverables:** Network isolation, pod security, working eval runner, 13 total scenarios.

### Week 4: Audit Logging and Eval Completion

| # | Work Item | Gap | Priority | Effort | Dimension Impact |
|---|-----------|-----|----------|--------|------------------|
| 4.1 | Define audit event schema | GAP-002 | MUST | 4h | Safety 3.0→3.5 |
| 4.2 | Implement structured audit logging to PVC | GAP-002 | MUST | 16h | Safety |
| 4.3 | Write eval scenarios for remaining 9 skills | GAP-001 | MUST | 16h | Testing 2.5→3.5 |
| 4.4 | Add eval step to CI pipeline | GAP-001 | MUST | 4h | CI/CD 2.0→2.5 |
| 4.5 | Write 3 adversarial safety-boundary scenarios | GAP-001 | MUST | 6h | Testing 3.5→4.0 |

**Week 4 deliverables:** Audit trail, 25+ eval scenarios, eval in CI.

### H1 Exit Criteria

- [ ] All documentation links valid, all counts accurate
- [ ] Semver adopted, v0.1.0+ tagged, container images versioned
- [ ] GitHub Release workflow functional
- [ ] NetworkPolicy and PodSecurity in place
- [ ] Audit logging to PVC operational
- [ ] 22+ eval scenarios (1 per skill minimum)
- [ ] Automated eval runner functional
- [ ] Eval integrated into CI pipeline
- [ ] `_context/` knowledge base established and accurate

**Expected maturity scores after H1:**

| Dimension | Before | After |
|-----------|-------:|------:|
| Testing/Eval | 1.0 | 3.5 |
| Release/Versioning | 1.0 | 3.5 |
| Safety/Governance | 3.0 | 3.5 |
| Security | 2.0 | 3.0 |
| Documentation | 2.5 | 3.5 |
| CI/CD | 2.0 | 2.5 |
| **Overall** | **2.0** | **3.0** |

---

## Horizon 2: Capability Expansion (Weeks 5-12)

> Theme: "Complete the lifecycle and make it observable."
> Goal: Raise maturity from 3.0 to 3.8/5.0.
> MoSCoW: Mix of SHOULD and high COULD items.

### Sprint 1 (Weeks 5-6): Train and Evaluate Skills

| # | Work Item | Gap | Effort |
|---|-----------|-----|--------|
| 5.1 | Build `train/distributed-training-setup` skill | GAP-006 | 12h |
| 5.2 | Build `train/training-job-monitor` skill | GAP-006 | 8h |
| 5.3 | Build `evaluate/model-benchmarker` skill (LM-Eval) | GAP-006 | 12h |
| 5.4 | Eval scenarios for all 3 new skills | GAP-001 | 6h |
| 5.5 | Update kustomization.yaml + Hermes mounts | GAP-006 | 2h |

### Sprint 2 (Weeks 7-8): Safety Skills and Multi-Model

| # | Work Item | Gap | Effort |
|---|-----------|-----|--------|
| 6.1 | Build `maintain-safety/guardrails-validator` skill | GAP-006 | 12h |
| 6.2 | Build `maintain-safety/compliance-checker` skill | GAP-006 | 8h |
| 6.3 | Build `evaluate/bias-detector` skill | GAP-006 | 10h |
| 6.4 | Document multi-model provider configurations | GAP-009/ADR-003 | 8h |
| 6.5 | Test skill behavior across 3 model providers | GAP-009 | 12h |
| 6.6 | Eval scenarios for 3 new skills | GAP-001 | 6h |

### Sprint 3 (Weeks 9-10): Observability

| # | Work Item | Gap | Effort |
|---|-----------|-----|--------|
| 7.1 | Add OpenTelemetry SDK to Containerfile | GAP-007 | 4h |
| 7.2 | Instrument MCP tool calls with trace spans | GAP-007 | 16h |
| 7.3 | Expose Prometheus metrics endpoint | GAP-007 | 8h |
| 7.4 | Create ServiceMonitor for OpenShift monitoring | GAP-007 | 4h |
| 7.5 | Implement structured JSON logging | GAP-007 | 8h |
| 7.6 | Add token usage tracking | GAP-007 | 4h |

### Sprint 4 (Weeks 11-12): Alerting and Workflow Engine

| # | Work Item | Gap | Effort |
|---|-----------|-----|--------|
| 8.1 | Implement Slack webhook for workflow escalations | GAP-008 | 8h |
| 8.2 | Implement PagerDuty integration | GAP-008 | 8h |
| 8.3 | Formalize Hermes cron commands to match workflow YAML | GAP-010/ADR-006 | 12h |
| 8.4 | Create disconnected Kustomize overlay | ADR-007 | 8h |
| 8.5 | End-to-end disconnected deployment test | ADR-007 | 8h |

### H2 Exit Criteria

- [ ] All 9 lifecycle phases have at least 2 skills
- [ ] 28+ skills total (22 existing + 6 new)
- [ ] 30+ eval scenarios
- [ ] Multi-model tested with 3+ providers
- [ ] OpenTelemetry traces for all MCP tool calls
- [ ] Prometheus metrics endpoint live
- [ ] Alerting integrations functional (Slack + PagerDuty)
- [ ] Disconnected overlay exists and tested
- [ ] Structured JSON logging operational

**Expected maturity scores after H2:**

| Dimension | Before | After |
|-----------|-------:|------:|
| Core Functionality | 3.0 | 4.0 |
| Testing/Eval | 3.5 | 4.0 |
| Observability | 1.0 | 3.5 |
| Disconnected | 2.5 | 4.0 |
| Extensibility | 2.0 | 2.5 |
| Ops Maturity | 2.0 | 3.5 |
| **Overall** | **3.0** | **3.8** |

---

## Horizon 3: Enterprise Scale (Weeks 13-24)

> Theme: "Scale to fleet and build ecosystem."
> Goal: Raise maturity from 3.8 to 4.5/5.0.
> MoSCoW: COULD items, driven by customer demand.

### Planned Work Streams

| Stream | Work Items | Gap | Timeline |
|--------|-----------|-----|----------|
| Multi-Tenancy | Namespace isolation, tenant RBAC, data separation, usage quotas | GAP-011 | Weeks 13-16 |
| Skill Ecosystem | Skill versioning, dependency management, community registry, SDK | GAP-012 | Weeks 15-20 |
| Advanced Eval | Adversarial testing, red-team scenarios, compliance benchmarks, multi-model eval matrix | GAP-001+ | Weeks 17-20 |
| Alternative Runtime | LangGraph implementation, skill adapter layer | GAP-013 | Weeks 18-22 |
| Enterprise Auth | SSO integration (OIDC/SAML), role-based agent access | New | Weeks 19-22 |
| SLA Framework | SLO definitions, error budgets, automated SLA reporting | New | Weeks 21-24 |
| Feedback Loop | User satisfaction tracking, skill effectiveness metrics, NPS | New | Weeks 22-24 |

---

## Roadmap Visualization

```
Week  1    2    3    4  │  5    6    7    8    9   10   11   12  │ 13        18        24
──────────────────────────────────────────────────────────────────────────────────────────
H1: Foundation Hardening │ H2: Capability Expansion               │ H3: Enterprise Scale
                         │                                        │
[Doc Fixes─────]         │                                        │
[Semver/Release────────] │                                        │
      [Security──────]   │                                        │
      [Eval Runner───────────]                                    │
            [Audit Log────]                                       │
                         │[Train/Eval Skills────]                 │
                         │      [Safety Skills + Multi-Model───]  │
                         │            [Observability──────────]   │
                         │                  [Alerting+Workflow──] │
                         │                  [Disconnected─────]   │
                         │                                        │[Multi-Tenancy──────]
                         │                                        │   [Skill Ecosystem────────]
                         │                                        │      [Advanced Eval──────]
                         │                                        │         [Alt Runtime──────]
                         │                                        │            [Enterprise Auth──]
                         │                                        │               [SLA Framework──]
```

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Hermes SDK limitations block workflow engine | Medium | High | ADR-006 Option B (custom executor) as fallback |
| Eval runner LLM cost is prohibitive | Medium | Medium | Use cheaper model for eval; cache deterministic tool calls |
| Multi-model behavior inconsistency | High | Medium | Establish minimum model capability requirements; eval-gate per model |
| Disconnected testing requires dedicated air-gapped lab | High | High | Simulate with NetworkPolicy + local registry; partner with customer for real test |
| Security hardening breaks existing deployment | Low | High | Feature flags for NetworkPolicy; test in staging first |
| Community skill contributions lack quality | Medium | Medium | Skill SDK with lint + eval as gatekeeping; curator review process |

---

## Success Metrics

### H1 (Week 4)
- Eval pass rate >= 80% across all skills
- Zero broken documentation links
- Release process used for at least 1 tagged release
- Audit log captures 100% of Tier 2 operations

### H2 (Week 12)
- All 9 lifecycle phases populated with skills
- p95 MCP tool call latency tracked and < 5s
- Alerting delivers to Slack within 60s of workflow trigger
- Multi-model eval shows < 10% behavior variance across 3 providers

### H3 (Week 24)
- Multi-tenant deployment serving 3+ teams
- Skill marketplace with 5+ community contributions
- SLA compliance reporting automated
- User satisfaction NPS > 40
