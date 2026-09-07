# 07 — Exploration Log

> Running log of codebase exploration, findings, and open questions.
> Use this file to resume work after context window resets.
> Last updated: 2026-08-22

---

## How to Use This File

1. **On context reset:** Read this file FIRST, then `00-CODEBASE-MAP.md` for structural context
2. **During exploration:** Append findings to the relevant section below
3. **After changes:** Update the "Last Verified" dates for affected areas
4. **Open questions:** Track unresolved items in the Questions section at the bottom

---

## Exploration History

### 2026-08-22 — Initial Full Codebase Exploration

**Explorer:** AI Agent (Cursor)
**Scope:** Complete repository exploration — all directories, all files
**Method:** Parallel exploration agents covering 5 areas simultaneously

#### Areas Explored

| Area | Files Read | Status | Last Verified |
|------|-----------|--------|---------------|
| `agent/` (3 files) | soul.md, rules.md, config.yaml | Complete | 2026-08-22 |
| `skills/` (22 SKILL.md + spec + template + scripts) | All SKILL.md files, SKILL_SPEC.md, _template | Complete | 2026-08-22 |
| `workflows/` (3 YAML + README) | All files | Complete | 2026-08-22 |
| `runtimes/` (14 files) | Containerfile, deployment, entrypoint, kustomization, READMEs | Complete | 2026-08-22 |
| `mcp-servers/` (10 files) | All READMEs, deployments, Containerfile | Complete | 2026-08-22 |
| `eval/` (5 files) | All scenarios, rubric, README | Complete | 2026-08-22 |
| `personas/` (5 files) | All persona .md files | Complete | 2026-08-22 |
| `docs/` (10 files) | All docs across 4 subdirs | Complete | 2026-08-22 |
| `examples/` (4 files) | All example READMEs | Complete | 2026-08-22 |
| `.github/` (4 files) | Workflows + issue templates | Complete | 2026-08-22 |
| Root files (8) | Makefile, kustomization.yaml, README, etc. | Complete | 2026-08-22 |

**Total files explored:** ~107

#### Key Findings

1. **Strong foundation:** Agent identity (soul + rules + config) is well-designed with clear tiered autonomy
2. **Good skill coverage for Platform Engineer and SRE** — 8 and 7 skills respectively
3. **Critical gaps in Data Scientist persona** — train and evaluate phases completely empty
4. **AI Engineer has RHOAI 3.5 feature gaps** — OGX, Garak, LM-Eval, AutoRAG not covered
5. **Eval is dangerously thin** — 3 scenarios for 22 skills is 14% coverage
6. **make eval is a stub** — counts files but executes nothing
7. **Documentation has multiple broken links** and phantom path references
8. **Hermes is the only functional runtime** — LangGraph and CrewAI are README placeholders
9. **Workflow YAML is documentation, not executable** — Hermes cron is the actual scheduler
10. **Two distinct skill styles:** MCP-centric (Hermes frontmatter) vs operational (shell scripts for MaaS)
11. **Disconnected support is conceptually strong but implementation incomplete** — missing overlays and profiles
12. **No release process** — CHANGELOG empty, images tagged `latest` only, no semver
13. **No observability** — dashboard exists but no metrics, traces, or structured logging
14. **No audit trail** — agent actions not logged for compliance

#### Quantitative Summary

| Metric | Count |
|--------|------:|
| Total skills | 22 |
| Active lifecycle phases | 6 of 9 |
| Empty lifecycle phases | 3 (train, evaluate, maintain-safety) |
| Planned-but-unbuilt skills | 9 |
| MCP servers | 5 |
| Whitelisted MCP tools | ~90 |
| Workflows | 3 (2 cron, 1 manual) |
| Eval scenarios | 3 |
| Personas defined | 5 |
| Personas with eval coverage | 2 of 5 |
| Documentation files | 10 |
| Example interactions | 4 |
| CI workflows | 2 |
| Known broken doc links | 3 |
| Phantom path references | 2 (agent/profiles/, overlays/disconnected/) |

---

## Context Files Created

| File | Content | Status |
|------|---------|--------|
| `00-CODEBASE-MAP.md` | Full structural inventory | Complete |
| `01-PRODUCT-ASSESSMENT.md` | 12-dimension maturity scoring (2.0/5.0 overall) | Complete |
| `02-PERSONA-JTBD.md` | Jobs-to-be-Done per persona with coverage gaps | Complete |
| `03-SKILL-COVERAGE-MATRIX.md` | Phase x Persona heatmap + skill-level mapping | Complete |
| `04-GAP-ANALYSIS.md` | 15 RICE-scored gaps with work items | Complete |
| `05-ARCHITECTURE-DECISIONS.md` | 7 ADRs (3 accepted, 2 proposed, 3 pending) | Complete |
| `06-ROADMAP.md` | 3-horizon plan with week-by-week breakdown | Complete |
| `07-EXPLORATION-LOG.md` | This file | Complete |

---

## Open Questions

### Architecture
- [ ] Does Hermes SDK support plugin hooks for tool call interception? (needed for ADR-004 observability decision)
- [ ] Can Hermes cron natively parse workflow YAML or does it need a separate executor? (ADR-006)
- [ ] What is the Hermes session model — does it support user-scoped contexts for multi-tenancy? (ADR-005)
- [ ] Are the `kanban: false` and `memory.providers: []` config values intentional or placeholder?

### Skills
- [ ] Why do MaaS skills (maas-enable, maas-deploy-model, maas-debug) use shell scripts instead of MCP tools? Is there a MaaS MCP server planned?
- [ ] The `rhoai-disconnected-deploy` skill references 3 modes (deploy, pre-flight, diagnose) — are these modes actually functional in Hermes?
- [ ] Several skills reference MCP tools not in the config.yaml whitelist (e.g., `mcp_openshift_resources_list`) — does Hermes resolve these dynamically?

### Infrastructure
- [ ] The MLflow MCP Containerfile installs `mlflow[mcp]==3.15.0` — is this version compatible with the MLflow deployed in the cluster?
- [ ] OpenShift MCP server uses `quay.io/rbrhssa/openshift-mcp-server:latest` — what is the source repo?
- [ ] The entrypoint.sh does `envsubst` on config.yaml and strips MCP servers with empty URLs — has this been tested with all 5 servers configured vs partial?

### Documentation
- [ ] Should `agent/profiles/` be created or should references be removed? (need to decide in ADR-007)
- [ ] Should `runtimes/hermes/overlays/disconnected/` be created or should references be removed?
- [ ] The README mentions "22 skills" but architecture.md says "19" — which was the original intent and when did the count drift?

### Eval
- [ ] What LLM should power the eval runner? Using the same model (Gemini) risks circular evaluation
- [ ] Should eval scenarios include expected cost bounds (max tool calls, max tokens)?
- [ ] How should eval handle skills that require a live cluster (mock MCP responses vs real cluster)?

---

## Next Actions (When Resuming)

If context is reset and you're picking up this work:

1. **Read this file first** — understand what was explored and what's outstanding
2. **Read `06-ROADMAP.md`** — understand current phase and priorities
3. **Check git log** — see what was committed since last exploration
4. **Start with H1 Week 1 items** — doc fixes are the quickest wins (see roadmap)
5. **Resolve open questions** — prioritize architecture questions that block ADR decisions

---

## Execution Log

### 2026-08-22 — Week 1: Quick Wins and Trust Fixes (COMPLETED)

| Item | Status | Files Changed |
|------|--------|---------------|
| 1.1 Fix broken doc links (3 locations) | DONE | README.md, troubleshooting.md, deployment-guide.md |
| 1.2 Update skill count 19→22 | DONE | architecture.md |
| 1.3 Fix ArgoCD credential docs | DONE | obtaining-credentials.md (ConfigMap→CR) |
| 1.4 Create agent/profiles/ | DONE | agent/profiles/connected.env, disconnected.env |
| 1.4b Create disconnected overlay | DONE | runtimes/hermes/overlays/disconnected/kustomization.yaml |
| 1.5 Create _context/ knowledge base | DONE | 8 context files |
| 1.6 Adopt semver | DONE | CHANGELOG.md (v0.1.0) |

### 2026-08-22 — Week 2: Release Engineering and CI (COMPLETED)

| Item | Status | Files Changed |
|------|--------|---------------|
| 2.1 Version-tagged container images | DONE | .github/workflows/build-image.yaml (semver+sha tags) |
| 2.2 GitHub Release workflow | DONE | .github/workflows/release.yaml (new) |
| 2.3 Compatibility matrix | DONE | docs/reference/compatibility-matrix.md (new) |
| 2.4 Eval scenario template | DONE | eval/scenarios/_template.yaml (new) |
| 2.5 5 new eval scenarios | DONE | platform-status-report, install-validation, workbench-startup-failure, incident-operator-degraded, maas-model-deployment |

**Eval coverage after Week 2:** 8 scenarios covering 4 of 5 personas (missing: mlops-engineer) and 5 of 9 phases.

### 2026-08-22 — Week 3: Security and Eval Foundation (COMPLETED)

| Item | Status | Files Changed |
|------|--------|---------------|
| 3.1 NetworkPolicy for rhoai-copilot namespace | DONE | runtimes/base/networkpolicy.yaml (new — agent + RHOAI MCP policies) |
| 3.2 NetworkPolicy for MCP server namespaces | DONE | mcp-servers/openshift/networkpolicy.yaml, mcp-servers/mlflow/networkpolicy.yaml (new) |
| 3.3 PodSecurity restricted labels | DONE | runtimes/base/namespace.yaml, mcp-servers/openshift/deployment.yaml (labels added) |
| 3.3b Wire NetworkPolicy into Kustomize | DONE | kustomization.yaml (added networkpolicy.yaml to resources) |
| 3.4 Build make eval runner MVP | DONE | eval/run_eval.py (new), Makefile (eval targets updated) |
| 3.5 5 new eval scenarios | DONE | capacity-forecast, serving-runtime-selection, dsc-component-inspection, daily-health-report, model-promotion |

**Eval coverage after Week 3:** 13 scenarios covering 5/5 personas and 7 phases. All personas now have eval coverage.

### 2026-08-22 — Week 4: Audit Logging and Eval Completion (COMPLETED)

| Item | Status | Files Changed |
|------|--------|---------------|
| 4.1 Audit event schema + logger | DONE | scripts/audit-logger.py (new), docs/reference/audit-logging.md (new) |
| 4.2 Wire audit into entrypoint | DONE | runtimes/hermes/entrypoint.sh (audit init block added) |
| 4.3 9 remaining eval scenarios | DONE | disconnected-diagnosis, gitops-config-generation, training-resource-plan, upgrade-readiness, pipeline-failure-debug, experiment-comparison, maas-bootstrap, model-lifecycle-tracking, maas-troubleshooting |
| 4.4 Add eval to CI | DONE | .github/workflows/validate.yaml (validate-eval job added) |
| 4.5 3 adversarial scenarios | DONE | adversarial-delete-request, adversarial-direct-mutation, adversarial-credential-extraction |

**Eval coverage after Week 4:** 25 scenarios. 22/22 skills covered (100%). 5/5 personas. 3 adversarial safety tests. Eval in CI.

### HORIZON 1 COMPLETE

All H1 exit criteria met:
- [x] All documentation links valid, all counts accurate
- [x] Semver adopted, v0.1.0 in CHANGELOG
- [x] GitHub Release workflow functional
- [x] NetworkPolicy and PodSecurity in place
- [x] Audit logging to PVC operational
- [x] 25 eval scenarios (22 skill + 3 adversarial)
- [x] Automated eval runner functional
- [x] Eval integrated into CI pipeline
- [x] _context/ knowledge base established and accurate

---

## Change Log for This File

| Date | Change |
|------|--------|
| 2026-08-22 | Initial full codebase exploration completed. All 8 context files created. |
| 2026-08-22 | Week 1 and Week 2 execution completed. Updated with execution log. |
| 2026-08-22 | Week 3 execution completed. Security hardening + eval runner + 5 new scenarios. |
| 2026-08-22 | Week 4 execution completed. Audit logging + 100% eval coverage + CI integration. H1 COMPLETE. |
