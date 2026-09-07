# 03 — Skill Coverage Matrix

> Skills mapped across Lifecycle Phases x Personas with coverage density.
> Last updated: 2026-08-22

---

## Coverage Heat Map

```
                          PlatEng    SRE     DataSci   MLOps    AIEng
                         ────────  ───────  ────────  ───────  ───────
platform-setup (4)        ████      ░░       ░░        ░░       ░░
plan           (3)        ██        ██       ██        ███      ███
administer     (3)        ████      ██       ░░        ░░       ░░
develop        (3)        ░░        ░░       ████      ██       ██
train          (0)        ░░        ░░       ░░        ░░       ░░    ◄ EMPTY
evaluate       (0)        ░░        ░░       ░░        ░░       ░░    ◄ EMPTY
deploy         (4)        ░░        ░░       ░░        ████     ████
monitor        (5)        ██        ████     ░░        ██       ██
maintain-safety(0)        ░░        ░░       ░░        ░░       ░░    ◄ EMPTY
                         ────────  ───────  ────────  ───────  ───────
Skills mapped:            8         7        4         7        9
Phases covered:           3/9       3/9      2/9       4/9      4/9
```

Legend: `████` = primary coverage (3+ skills), `███` = strong (2 skills), `██` = partial (1 skill), `░░` = no coverage

---

## Detailed Skill-to-Persona Mapping

### platform-setup (4 skills)

| Skill | PlatEng | SRE | DataSci | MLOps | AIEng |
|-------|:-------:|:---:|:-------:|:-----:|:-----:|
| rhoai-disconnected-deploy | **P** | — | — | — | — |
| rhoai-disconnected-helper | **P** | — | — | — | — |
| rhoai-install-validator | **P** | — | — | — | — |
| gitops-config-generator | **P** | — | — | — | — |

P = Primary user, S = Secondary user

### plan (3 skills)

| Skill | PlatEng | SRE | DataSci | MLOps | AIEng |
|-------|:-------:|:---:|:-------:|:-----:|:-----:|
| capacity-forecaster | S | **P** | — | **P** | **P** |
| training-planner | — | — | **P** | **P** | **P** |
| serving-runtime-advisor | — | — | — | **P** | **P** |

### administer (3 skills)

| Skill | PlatEng | SRE | DataSci | MLOps | AIEng |
|-------|:-------:|:---:|:-------:|:-----:|:-----:|
| rhoai-platform-status | **P** | **P** | — | — | — |
| rhoai-dsc-inspector | **P** | — | — | — | — |
| rhoai-upgrade-advisor | **P** | **P** | — | — | — |

### develop (3 skills)

| Skill | PlatEng | SRE | DataSci | MLOps | AIEng |
|-------|:-------:|:---:|:-------:|:-----:|:-----:|
| workbench-troubleshooter | — | — | **P** | — | — |
| pipeline-debugger | — | — | **P** | **P** | — |
| experiment-tracker | — | — | **P** | **P** | **P** |

### train (0 skills — EMPTY)

| Planned Skill | PlatEng | SRE | DataSci | MLOps | AIEng |
|---------------|:-------:|:---:|:-------:|:-----:|:-----:|
| *distributed-training-setup* | — | — | **P** | **P** | S |
| *training-job-monitor* | — | — | **P** | **P** | S |
| *hyperparameter-tuner* | — | — | **P** | S | S |

### evaluate (0 skills — EMPTY)

| Planned Skill | PlatEng | SRE | DataSci | MLOps | AIEng |
|---------------|:-------:|:---:|:-------:|:-----:|:-----:|
| *model-benchmarker* | — | — | **P** | **P** | **P** |
| *bias-detector* | — | — | **P** | S | **P** |
| *ab-test-analyzer* | — | — | — | **P** | **P** |

### deploy (4 skills)

| Skill | PlatEng | SRE | DataSci | MLOps | AIEng |
|-------|:-------:|:---:|:-------:|:-----:|:-----:|
| maas-enable | — | — | — | — | **P** |
| maas-deploy-model | — | — | — | — | **P** |
| rhoai-model-lifecycle | — | — | — | **P** | **P** |
| model-promotion-workflow | — | — | — | **P** | **P** |

### monitor (5 skills)

| Skill | PlatEng | SRE | DataSci | MLOps | AIEng |
|-------|:-------:|:---:|:-------:|:-----:|:-----:|
| argocd-health-check | **P** | **P** | — | S | — |
| argocd-diagnose-sync | **P** | **P** | — | — | — |
| daily-report-generator | S | **P** | — | — | — |
| incident-runbook | — | **P** | — | — | — |
| maas-debug | — | — | — | — | **P** |

### maintain-safety (0 skills — EMPTY)

| Planned Skill | PlatEng | SRE | DataSci | MLOps | AIEng |
|---------------|:-------:|:---:|:-------:|:-----:|:-----:|
| *guardrails-validator* | — | — | — | — | **P** |
| *model-card-generator* | — | — | S | **P** | **P** |
| *compliance-checker* | S | — | — | **P** | **P** |

---

## MCP Tool Coverage by Phase

| Phase | ArgoCD | RHOAI | OpenShift | MLflow | GitHub | Shell/oc |
|-------|:------:|:-----:|:---------:|:------:|:------:|:--------:|
| platform-setup | X | X | X | — | — | — |
| plan | — | X | X | — | — | — |
| administer | X | — | — | — | — | — |
| develop | — | X | X | X | — | — |
| train | — | — | — | — | — | — |
| evaluate | — | — | — | — | — | — |
| deploy | X | X | — | X | X | X |
| monitor | X | X | X | — | — | X |
| maintain-safety | — | — | — | — | — | — |

---

## Workflow Skill Reuse

Skills that appear in workflow step definitions:

| Skill | daily-health | drift-detection | incident-response |
|-------|:---:|:---:|:---:|
| monitor/argocd-health-check | X | X | X |
| monitor/argocd-diagnose-sync | — | X | X |
| monitor/daily-report-generator | X | X | — |
| administer/rhoai-platform-status | X | — | X |
| administer/rhoai-dsc-inspector | — | — | X |
| develop/workbench-troubleshooter | X | — | — |
| deploy/rhoai-model-lifecycle | X | — | — |
| platform-setup/rhoai-disconnected-helper | — | — | X (conditional) |
| monitor/incident-runbook | — | — | X |

**9 of 22 skills** are referenced in workflows. The remaining 13 are standalone interactive skills.

---

## Eval Scenario Coverage

| Scenario | Persona | Phase | Skill | Scoring Dimensions |
|----------|---------|-------|-------|--------------------|
| diagnose-sync-failure | platform-engineer | monitor | argocd-diagnose-sync | accuracy, completeness, safety, tool_efficiency |
| disconnected-deploy-guidance | platform-engineer | install | rhoai-disconnected-deploy | accuracy, completeness, safety, disconnected_awareness |
| platform-health-check | sre | monitor | argocd-health-check | accuracy, completeness, safety, presentation |

**Coverage gaps:**
- 0 scenarios for data-scientist, mlops-engineer, ai-engineer (3 of 5 personas)
- 3 of 22 skills have eval scenarios (14% coverage)
- 0 scenarios for plan, administer, develop, deploy phases
- 0 scenarios for workflow orchestration
- 0 adversarial / safety-boundary scenarios

---

## Priority Skill Development Recommendations

Based on JTBD analysis and coverage gaps:

### Tier 1 — High Impact (fills empty phases, unblocks personas)

| New Skill | Phase | Primary Persona | Impact |
|-----------|-------|-----------------|--------|
| distributed-training-setup | train | Data Scientist | Unblocks entire train phase |
| training-job-monitor | train | Data Scientist | Core DS workflow enablement |
| model-benchmarker | evaluate | AI Engineer | LM-Eval integration for RHOAI 3.5 |
| guardrails-validator | maintain-safety | AI Engineer | Safety compliance for GenAI |

### Tier 2 — High Value (enhances existing capabilities)

| New Skill | Phase | Primary Persona | Impact |
|-----------|-------|-----------------|--------|
| alerting-integration | monitor | SRE | Wires workflow escalations to real systems |
| model-drift-monitor | monitor | MLOps | Production model quality tracking |
| rag-pipeline-builder | develop | AI Engineer | OGX/AutoRAG for RHOAI 3.5 |
| hyperparameter-tuner | train | Data Scientist | Automated HPO |

### Tier 3 — Nice to Have (progressive delivery, advanced ops)

| New Skill | Phase | Primary Persona | Impact |
|-----------|-------|-----------------|--------|
| canary-deployment | deploy | MLOps | Progressive delivery patterns |
| bias-detector | evaluate | Data Scientist | Fairness analysis |
| compliance-checker | maintain-safety | MLOps | Regulatory compliance |
| model-card-generator | maintain-safety | MLOps | Documentation automation |
