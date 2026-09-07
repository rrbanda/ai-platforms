# 02 — Persona Jobs-to-be-Done Analysis

> Maps each persona's jobs against available skills to identify coverage and unmet needs.
> Framework: Jobs-to-be-Done (JTBD) — what outcomes does each persona hire the agent to achieve?
> Last updated: 2026-08-22

---

## Persona Overview

| Persona | Primary Focus | Lifecycle Phases | MCP Servers | Skills Available | Skills Needed |
|---------|--------------|-----------------|-------------|:----------------:|:-------------:|
| Platform Engineer | Install, configure, maintain RHOAI | Install, Administer, Monitor | ArgoCD, OpenShift, GitHub | 8 | 2-3 |
| SRE | Reliability, incidents, capacity | Monitor, Administer, Plan | ArgoCD, OpenShift, RHOAI, MLflow | 7 | 3-4 |
| Data Scientist | Experiments, training, quality | Develop, Train, Evaluate | RHOAI, MLflow, OpenShift | 4 | 6-8 |
| MLOps Engineer | Pipelines, serving, promotion | Deploy, Develop, Plan, Monitor | RHOAI, MLflow, ArgoCD, GitHub | 7 | 3-4 |
| AI Engineer | GenAI apps, MaaS, RAG, guardrails | Deploy, Develop, Evaluate, Plan, Safety | RHOAI, MLflow, ArgoCD, GitHub | 9 | 5-7 |

---

## Platform Engineer

### Role Definition
Responsible for installing, configuring, and maintaining the RHOAI platform on OpenShift. Manages operator lifecycle, cluster resources, RBAC, and GitOps pipelines.

### Jobs-to-be-Done

| # | Job | Frequency | Current Skill | Coverage |
|---|-----|-----------|---------------|----------|
| J1 | Deploy RHOAI on a new cluster (connected) | Occasional | `rhoai-install-validator`, `gitops-config-generator` | COVERED |
| J2 | Deploy RHOAI on an air-gapped cluster | Occasional | `rhoai-disconnected-deploy`, `rhoai-disconnected-helper` | COVERED |
| J3 | Validate installation completeness | Per deploy | `rhoai-install-validator` | COVERED |
| J4 | Generate/modify DSC configuration | As needed | `gitops-config-generator` | COVERED |
| J5 | Inspect DSC health and drift | Daily | `rhoai-dsc-inspector` | COVERED |
| J6 | Check full platform status | Daily | `rhoai-platform-status` | COVERED |
| J7 | Plan and execute upgrades | Quarterly | `rhoai-upgrade-advisor` | PARTIAL — advisor only, no execution |
| J8 | Diagnose sync failures | Reactive | `argocd-diagnose-sync` | COVERED |
| J9 | Monitor ArgoCD health | Continuous | `argocd-health-check` | COVERED |
| J10 | Provision new cluster with RHOAI | Occasional | — | GAP |
| J11 | Manage operator subscriptions | Quarterly | — | GAP — partially in upgrade-advisor |
| J12 | Configure RBAC for data science teams | Occasional | — | GAP |

### Unmet Needs
- **Automated upgrade execution:** Current advisor only assesses readiness; cannot execute the upgrade steps
- **Cluster provisioning:** No skill for bootstrapping a new OCP cluster before RHOAI install
- **RBAC management:** No skill for creating/managing namespace-scoped roles for DS teams
- **Multi-cluster config management:** No skill for managing consistent config across fleet

### Eval Coverage
- 2 of 3 eval scenarios target this persona (diagnose-sync-failure, disconnected-deploy-guidance)
- Missing: install validation scenario, DSC config generation scenario, upgrade advisory scenario

---

## SRE / Operations

### Role Definition
Responsible for platform reliability, incident response, and operational visibility. Focuses on uptime, alerting, capacity management, and rapid troubleshooting.

### Jobs-to-be-Done

| # | Job | Frequency | Current Skill | Coverage |
|---|-----|-----------|---------------|----------|
| J1 | Check overall platform health | Daily | `argocd-health-check` | COVERED |
| J2 | Generate daily health reports | Daily | `daily-report-generator` | COVERED |
| J3 | Respond to platform incidents | Reactive | `incident-runbook` | COVERED |
| J4 | Diagnose specific sync failures | Reactive | `argocd-diagnose-sync` | COVERED |
| J5 | Monitor platform status | Continuous | `rhoai-platform-status` | COVERED |
| J6 | Forecast capacity exhaustion | Weekly | `capacity-forecaster` | COVERED |
| J7 | Assess upgrade risk | Quarterly | `rhoai-upgrade-advisor` | COVERED |
| J8 | Receive alerts on degradation | Continuous | — | GAP — escalation hooks exist but no integration |
| J9 | Track SLOs and error budgets | Continuous | — | GAP |
| J10 | Perform change management | As needed | — | GAP |
| J11 | Correlate incidents across systems | Reactive | — | GAP — multi-MCP cross-reference is manual |
| J12 | Run post-incident reviews | Post-incident | — | GAP |
| J13 | Monitor model serving latency/errors | Continuous | — | GAP |

### Unmet Needs
- **Alerting integration:** Workflow escalation hooks (alert-channel, notify-oncall) are defined but not wired to Slack/PagerDuty/Teams
- **SLO tracking:** No SLO definitions, no error budget calculation, no burn-rate alerting
- **Change management:** No pre/post change validation or change window enforcement
- **Cross-system correlation:** Agent can query multiple MCPs but no skill explicitly correlates multi-source incidents
- **Model serving monitoring:** No skill for inference latency/error rate tracking

### Eval Coverage
- 1 of 3 eval scenarios targets this persona (platform-health-check)
- Missing: incident response scenario, capacity forecasting scenario, daily report scenario

---

## Data Scientist

### Role Definition
Focuses on experiment development, model training, and iterating on model quality. Needs workbench access, pipeline execution, and results tracking without deep platform knowledge.

### Jobs-to-be-Done

| # | Job | Frequency | Current Skill | Coverage |
|---|-----|-----------|---------------|----------|
| J1 | Fix workbench startup issues | Reactive | `workbench-troubleshooter` | COVERED |
| J2 | Compare experiment results | Per experiment | `experiment-tracker` | COVERED |
| J3 | Debug pipeline failures | Reactive | `pipeline-debugger` | COVERED |
| J4 | Estimate training resources | Pre-training | `training-planner` | COVERED |
| J5 | Submit and monitor training jobs | Per training | — | GAP — entire train phase empty |
| J6 | Configure distributed training | Occasional | — | GAP |
| J7 | Tune hyperparameters | Per experiment | — | GAP |
| J8 | Evaluate model quality metrics | Post-training | — | GAP — entire evaluate phase empty |
| J9 | Compare model performance | Post-training | — | GAP |
| J10 | Detect model bias | Pre-deploy | — | GAP |
| J11 | Find right notebook image | Per project | — | PARTIAL — list_notebook_images tool exists but no dedicated skill |
| J12 | Set up data connections | Per project | — | PARTIAL — create_s3_data_connection tool exists but no skill |

### Unmet Needs
- **Training lifecycle:** Cannot submit, monitor, or manage training jobs (train phase is empty)
- **Distributed training:** No skill for Ray/PyTorchJob/KuequeJob setup
- **Hyperparameter tuning:** No skill for automated or guided HPO
- **Model evaluation:** Cannot run evaluation benchmarks (evaluate phase is empty)
- **Bias detection:** No bias analysis or fairness checking
- **Model comparison:** Only MLflow metric comparison exists; no structured eval skill

### Eval Coverage
- 0 of 3 eval scenarios target this persona
- Missing: workbench troubleshooting scenario, experiment tracking scenario, pipeline debug scenario

### Priority Assessment
This persona has the **largest unmet needs** because 2 of their 3 primary phases (Train, Evaluate) have zero skills. The develop phase skills handle reactive troubleshooting but not proactive data science workflows.

---

## MLOps Engineer

### Role Definition
Responsible for the ML workflow infrastructure: model pipelines, serving runtimes, model promotion, and experiment management. Bridges the gap between data science and production.

### Jobs-to-be-Done

| # | Job | Frequency | Current Skill | Coverage |
|---|-----|-----------|---------------|----------|
| J1 | Promote models between environments | Per release | `model-promotion-workflow` | COVERED |
| J2 | Manage model serving lifecycle | Continuous | `rhoai-model-lifecycle` | COVERED |
| J3 | Select optimal serving runtime | Pre-deploy | `serving-runtime-advisor` | COVERED |
| J4 | Track experiments in MLflow | Per experiment | `experiment-tracker` | COVERED |
| J5 | Debug pipeline failures | Reactive | `pipeline-debugger` | COVERED |
| J6 | Plan training resources | Pre-training | `training-planner` | COVERED |
| J7 | Forecast infrastructure needs | Monthly | `capacity-forecaster` | COVERED |
| J8 | Perform A/B testing | Per release | — | GAP |
| J9 | Implement canary deployments | Per release | — | GAP |
| J10 | Automate rollback on degradation | Reactive | — | GAP — promotion skill has rollback guidance but not automated |
| J11 | Monitor model drift | Continuous | — | GAP |
| J12 | Manage feature stores | Occasional | — | GAP |
| J13 | Orchestrate ML pipelines end-to-end | Continuous | — | PARTIAL — debugger only, no pipeline creation/management |

### Unmet Needs
- **Progressive delivery:** No A/B testing or canary deployment skills
- **Automated rollback:** Model promotion has Git revert guidance but no automated rollback on metric degradation
- **Model drift detection:** No skill for monitoring inference quality degradation over time
- **Pipeline management:** Can debug failures but cannot create, modify, or manage pipelines
- **Feature store integration:** No skills for feature storage or retrieval

### Eval Coverage
- 0 of 3 eval scenarios target this persona
- Missing: model promotion scenario, pipeline management scenario, serving runtime scenario

---

## AI Engineer

### Role Definition
Builds production-ready AI and agentic applications on RHOAI. Works with model catalog, MaaS, OGX, llm-d. Focuses on model customization, serving at scale, and integrating models into applications via APIs.

### Jobs-to-be-Done

| # | Job | Frequency | Current Skill | Coverage |
|---|-----|-----------|---------------|----------|
| J1 | Enable MaaS on cluster | One-time | `maas-enable` | COVERED |
| J2 | Deploy model to MaaS | Per model | `maas-deploy-model` | COVERED |
| J3 | Manage model serving lifecycle | Continuous | `rhoai-model-lifecycle` | COVERED |
| J4 | Promote models between environments | Per release | `model-promotion-workflow` | COVERED |
| J5 | Select serving runtime | Pre-deploy | `serving-runtime-advisor` | COVERED |
| J6 | Estimate GPU/VRAM needs | Pre-deploy | `capacity-forecaster` | COVERED |
| J7 | Track fine-tuning experiments | Per experiment | `experiment-tracker` | COVERED |
| J8 | Plan fine-tuning resources | Pre-training | `training-planner` | COVERED |
| J9 | Debug MaaS issues | Reactive | `maas-debug` | COVERED |
| J10 | Build RAG pipelines with OGX | Per application | — | GAP |
| J11 | Configure guardrails | Per deployment | — | GAP — maintain-safety phase empty |
| J12 | Run security scans (Garak) | Pre-deploy | — | GAP |
| J13 | Benchmark models (LM-Eval) | Per model | — | GAP — evaluate phase empty |
| J14 | Use GenAI Playground | Interactive | — | GAP |
| J15 | Configure AutoRAG | Per application | — | GAP |
| J16 | Set up llm-d distributed inference | Per model | — | PARTIAL — serving-runtime-advisor mentions it but no dedicated skill |

### Unmet Needs
- **RAG pipeline construction:** OGX is a key RHOAI 3.5 feature but no skill supports it
- **Guardrails/safety:** Cannot configure content filtering or PII detection (maintain-safety empty)
- **Security scanning:** Garak integration mentioned in persona but no skill
- **Model benchmarking:** LM-Eval mentioned but no skill (evaluate phase empty)
- **GenAI playground guidance:** No interactive model experimentation skill
- **AutoRAG configuration:** Mentioned as key feature but no skill
- **Distributed inference:** llm-d setup not fully covered

### Eval Coverage
- 0 of 3 eval scenarios target this persona
- Missing: MaaS deployment scenario, model serving scenario, OGX/RAG scenario

---

## Cross-Persona Gap Heat Map

```
UNMET NEED                          PlatEng  SRE  DataSci  MLOps  AIEng
──────────────────────────────────  ───────  ───  ───────  ─────  ─────
Training lifecycle (submit/monitor)                  ███           
Distributed training setup                           ███           
Model evaluation / benchmarking                      ███    ██     ███
Bias / fairness detection                            ███           ███
Guardrails / content filtering                                     ███
RAG pipeline construction                                          ███
Security scanning (Garak)                                          ███
Alerting integration (Slack/PD)              ███                    
SLO tracking / error budgets                 ███                    
A/B testing / canary deploy                                 ███    
Automated rollback                                          ███    
Model drift monitoring                      ██              ███    
RBAC management                    ██                              
Cluster provisioning               ██                              
Change management                            ██                    
```

Legend: `███` = high-impact gap, `██` = moderate gap

---

## Strategic Implications

1. **Data Scientist is the most underserved persona** — 2 of 3 primary phases completely empty
2. **AI Engineer has the most RHOAI 3.5 gaps** — key new features (OGX, Garak, LM-Eval, AutoRAG) have no skills
3. **SRE lacks operational integrations** — workflows define escalation but nothing connects to real alerting
4. **Platform Engineer is best served** — 8 skills cover most primary jobs
5. **MLOps Engineer is well-served for current workflow** but lacks progressive delivery and automation
6. **Zero eval scenarios exist for 3 of 5 personas** — a critical quality gap
