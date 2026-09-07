# 00 — Codebase Map

> Definitive structural inventory of rhoai-copilot.
> Last updated: 2026-08-22

## Repository Identity

- **Name:** rhoai-copilot
- **Purpose:** AI agent for Red Hat OpenShift AI (RHOAI) platform lifecycle management via GitOps
- **License:** Apache 2.0
- **Owner:** @rrbanda (CODEOWNERS)
- **Validated on:** OCP 4.18 / RHOAI 3.5
- **Default runtime:** Hermes (python:3.13-slim)
- **Default model:** gemini-2.5-flash
- **Deploy target:** OpenShift via Kustomize (`oc apply -k .`)

---

## Directory Tree (depth 2)

```
rhoai-copilot/
├── agent/                         # Agent identity, safety rules, runtime config
│   ├── soul.md                    #   System prompt / personality
│   ├── rules.md                   #   Hard safety constraints (PROTECTED via CODEOWNERS)
│   └── config.yaml                #   Model, MCP servers, tool whitelist, harness features
├── skills/                        # Agentic skills by lifecycle phase (22 skills)
│   ├── SKILL_SPEC.md              #   Skill format specification
│   ├── _template/                 #   SKILL.md.template for new skills
│   ├── platform-setup/  (4)       #   Install/deploy RHOAI operators
│   ├── plan/            (3)       #   Capacity, runtime, training planning
│   ├── administer/      (3)       #   DSC, platform status, upgrades
│   ├── develop/         (3)       #   Workbenches, pipelines, experiments
│   ├── train/           (0)       #   PLACEHOLDER — planned only
│   ├── evaluate/        (0)       #   PLACEHOLDER — planned only
│   ├── deploy/          (4)       #   Model serving, MaaS, promotion
│   ├── monitor/         (5)       #   Health checks, drift, incidents, MaaS debug
│   └── maintain-safety/ (0)       #   PLACEHOLDER — planned only
├── workflows/                     # Multi-step autonomous procedures (3 workflows)
│   ├── daily-health-report.yaml   #   Cron 08:00 UTC — 5-step health pipeline
│   ├── drift-detection.yaml       #   Cron every 4h — sync drift analysis
│   └── incident-response.yaml     #   Manual — guided troubleshooting (6 steps)
├── runtimes/                      # Pluggable agent harness deployments
│   ├── base/                      #   Shared K8s resources (NS, RBAC, PVC, Svc, Route)
│   ├── hermes/                    #   PRODUCTION — Containerfile, deployment, entrypoint
│   ├── langgraph/                 #   PLANNED — README only
│   └── crewai/                    #   PLANNED — README only
├── mcp-servers/                   # MCP tool server configurations (5 servers)
│   ├── argocd/                    #   Docs only — stdio binary in agent image
│   ├── rhoai/                     #   Deployment + README (opendatahub-io/rhoai-mcp)
│   ├── openshift/                 #   Deployment + README (community)
│   ├── mlflow/                    #   Deployment + Containerfile + README
│   └── github/                    #   Docs only — stdio via npx
├── eval/                          # Evaluation scenarios and benchmarks
│   ├── scenarios/ (3)             #   diagnose-sync-failure, disconnected-deploy, health-check
│   └── scoring/rubric.md          #   Accuracy, completeness, safety, tool_efficiency
├── personas/          (5)         # Target user persona definitions
├── docs/                          # Documentation (10 files)
│   ├── getting-started/           #   quickstart.md, deployment-guide.md
│   ├── concepts/                  #   architecture.md, autonomy-tiers.md
│   ├── guides/                    #   mcp-server-setup, credentials, troubleshooting, etc.
│   └── reference/                 #   environment-variables.md
├── examples/          (4)         # Example interaction READMEs
├── scripts/                       # validate-deployment.sh
├── .github/                       # CI: validate.yaml, build-image.yaml, issue templates
├── Makefile                       # validate, build, push, deploy, eval (stub)
├── kustomization.yaml             # Root deploy: base + hermes + RHOAI MCP + 22 skill ConfigMaps
├── README.md                      # Project overview and docs index
├── CHANGELOG.md                   # Keep a Changelog (Unreleased only)
├── CONTRIBUTING.md                # Contribution guide
├── CODEOWNERS                     # @rrbanda owns all; strict on skills + rules.md
├── CODE_OF_CONDUCT.md             # Community conduct
├── SECURITY.md                    # Security policy
└── LICENSE                        # Apache 2.0
```

---

## File Counts by Area

| Area | Files | Status |
|------|------:|--------|
| agent/ | 3 | Complete |
| skills/ (SKILL.md) | 22 | 6 phases active, 3 placeholder |
| skills/ (scripts, configs, templates) | ~18 | MaaS skills have helper scripts |
| workflows/ | 3 + README | 2 cron, 1 manual |
| runtimes/ | 14 | Hermes active, LangGraph/CrewAI stubs |
| mcp-servers/ | 10 | 3 deployable, 2 docs-only |
| eval/ | 5 | 3 scenarios, 1 rubric, 1 README |
| personas/ | 5 | Complete |
| docs/ | 10 | Strong on deploy, thin on day-2 |
| examples/ | 4 | Narrative READMEs only |
| .github/ | 4 | 2 workflows, 2 issue templates |
| scripts/ | 1 | validate-deployment.sh |
| Root config | 8 | Makefile, kustomization, etc. |
| **Total** | **~107** | |

---

## Core Architecture Layers

```
┌──────────────────────────────────────────────────────┐
│                   Identity Layer                      │
│  soul.md (who)  │  rules.md (constraints)  │         │
│  config.yaml (runtime binding)                       │
├──────────────────────────────────────────────────────┤
│                  Capability Layer                     │
│  22 Skills (SKILL.md files by lifecycle phase)       │
│  3 Workflows (YAML orchestration of skills)          │
├──────────────────────────────────────────────────────┤
│                Infrastructure Layer                   │
│  Hermes Runtime (Containerfile + K8s manifests)      │
│  5 MCP Servers (ArgoCD, RHOAI, OpenShift, MLflow,   │
│                  GitHub)                              │
├──────────────────────────────────────────────────────┤
│                  Validation Layer                     │
│  3 Eval Scenarios  │  5 Personas  │  Scoring Rubric  │
├──────────────────────────────────────────────────────┤
│                 Documentation Layer                   │
│  10 docs files  │  4 examples  │  README index       │
└──────────────────────────────────────────────────────┘
```

---

## Skill Inventory (22 skills)

### platform-setup (4 skills)

| Skill | Purpose | MCP Servers |
|-------|---------|-------------|
| `rhoai-disconnected-deploy` | End-to-end air-gapped RHOAI deployment | ArgoCD, RHOAI |
| `rhoai-disconnected-helper` | Diagnose IDMS/ICSP, CatalogSource, ImagePull | OpenShift, ArgoCD |
| `rhoai-install-validator` | Pre/post install checklist validation | OpenShift, ArgoCD, RHOAI |
| `gitops-config-generator` | Generate Kustomize patches for DSC | RHOAI, ArgoCD |

### plan (3 skills)

| Skill | Purpose | MCP Servers |
|-------|---------|-------------|
| `capacity-forecaster` | GPU/CPU/memory utilization trends + exhaustion forecasts | OpenShift, RHOAI |
| `training-planner` | Training method selection + GPU sizing | OpenShift, RHOAI |
| `serving-runtime-advisor` | Recommend serving runtime by model/hardware | RHOAI, OpenShift |

### administer (3 skills)

| Skill | Purpose | MCP Servers |
|-------|---------|-------------|
| `rhoai-platform-status` | Full platform readiness across dependency layers | ArgoCD |
| `rhoai-dsc-inspector` | DSC component analysis + drift detection | ArgoCD |
| `rhoai-upgrade-advisor` | Upgrade readiness assessment | ArgoCD |

### develop (3 skills)

| Skill | Purpose | MCP Servers |
|-------|---------|-------------|
| `workbench-troubleshooter` | Notebook startup failure diagnosis | RHOAI, OpenShift |
| `pipeline-debugger` | DSPA health + pipeline step failures | RHOAI, OpenShift, ArgoCD |
| `experiment-tracker` | MLflow run comparison + best-model selection | MLflow, RHOAI |

### deploy (4 skills)

| Skill | Purpose | MCP Servers |
|-------|---------|-------------|
| `maas-enable` | One-time MaaS enablement on cluster | Shell/oc (not MCP) |
| `maas-deploy-model` | Deploy model to MaaS with governance + API key | Shell/oc + scripts |
| `rhoai-model-lifecycle` | Track GitOps model deployments | ArgoCD |
| `model-promotion-workflow` | GitOps promotion dev → staging → prod | RHOAI, MLflow, ArgoCD, GitHub |

### monitor (5 skills)

| Skill | Purpose | MCP Servers |
|-------|---------|-------------|
| `argocd-health-check` | Health/sync of all ArgoCD apps | ArgoCD |
| `argocd-diagnose-sync` | Deep-dive one app sync failure | ArgoCD |
| `daily-report-generator` | Daily/weekly platform health summary | ArgoCD, RHOAI, OpenShift |
| `incident-runbook` | Structured incident response + severity | RHOAI, ArgoCD, OpenShift |
| `maas-debug` | Diagnose/fix MaaS issues (Issues A-J) | Shell/oc |

### Placeholder Phases (0 skills each)

| Phase | Planned Skills (from READMEs) |
|-------|-------------------------------|
| `train/` | distributed-training-setup, training-job-monitor, hyperparameter-tuner |
| `evaluate/` | model-benchmarker, bias-detector, ab-test-analyzer |
| `maintain-safety/` | guardrails-validator, model-card-generator, compliance-checker |

---

## MCP Server Inventory

| Server | Transport | Tier | Tools | Deployment |
|--------|-----------|------|------:|------------|
| ArgoCD | stdio (binary) | 1+2 | 10 | Embedded in agent image |
| RHOAI | HTTP (streamable) | 1+2 | 35+ | `rhoai-copilot` namespace |
| OpenShift | HTTP (streamable) | 1 | 20+ | `ocp-mcp-server` namespace |
| MLflow | HTTP (streamable) | 1 | 15+ | `redhat-ods-applications` namespace |
| GitHub | stdio (npx) | 2 | 8 (whitelisted) | Embedded in agent image |

---

## Workflow Inventory

| Workflow | Trigger | Tier | Steps | Skills Used |
|----------|---------|------|------:|-------------|
| daily-health-report | Cron 08:00 UTC | 1 | 5 | argocd-health-check, rhoai-platform-status, workbench-troubleshooter, rhoai-model-lifecycle, daily-report-generator |
| drift-detection | Cron every 4h | 1 | 4 | argocd-health-check, argocd-diagnose-sync, (inline logic), daily-report-generator |
| incident-response | Manual | 1 | 6 | rhoai-platform-status, argocd-health-check, argocd-diagnose-sync, rhoai-dsc-inspector, rhoai-disconnected-helper (conditional), incident-runbook |

---

## CI/CD Pipeline

| Workflow | Trigger | Actions |
|----------|---------|---------|
| `validate.yaml` | Push/PR to main | Skill format checks, `kustomize build runtimes/base`, yamllint |
| `build-image.yaml` | Main path changes / manual | Build + push Hermes image to `ghcr.io` |

---

## Kustomize Deployment Structure

```
Root kustomization.yaml
├── Resources
│   ├── runtimes/base/ (namespace, rbac, pvc, service, route)
│   ├── runtimes/hermes/deployment.yaml
│   └── mcp-servers/rhoai/deployment.yaml
└── ConfigMapGenerator (25 ConfigMaps)
    ├── rhoai-copilot-entrypoint  (entrypoint.sh)
    ├── rhoai-copilot-soul        (agent/soul.md)
    ├── rhoai-copilot-config      (agent/config.yaml)
    └── skill-*                   (22 skill ConfigMaps)
```

---

## Known Issues and Inconsistencies

1. **Broken doc links:** `docs/guides/disconnected-setup.md` is referenced from wrong paths in README and other docs
2. **Phantom paths:** `agent/profiles/` and `runtimes/hermes/overlays/disconnected/` referenced but do not exist
3. **Stale count:** `docs/concepts/architecture.md` says 19 skills; actual count is 22
4. **ArgoCD credential docs conflict:** `obtaining-credentials.md` says edit ConfigMap; `mcp-server-setup.md` says patch CR
5. **Missing workflow YAML:** `model-promotion.yaml` listed in `workflows/README.md` but absent
6. **Missing template:** `workflows/_template/workflow.yaml.template` referenced but absent
7. **`make eval` is a stub:** prints scenario count, does not execute anything
8. **Train/evaluate/maintain-safety skills not mounted:** Hermes kustomization only mounts the 22 existing skills
