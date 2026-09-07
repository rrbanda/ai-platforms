---
name: release-handover-report
description: "Stakeholder report after a release: components deployed, checks run, environment status at handover."
version: 1.0.0
author: AgentHive Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [Release, Report, Stakeholders, Handover]
---

# Release Handover Report

MetLife "automated reports post deployments consolidating components
deployments, checks executed, environment status at the time of handover".

## Trigger Phrases

- "Write the handover report"
- "Release summary for stakeholders"
- Loaded after post-deploy validation

## Inputs

- PR URL / number and merge SHA if known
- YAML files shipped (`release-yaml-generator`)
- Review notes (`pr-review-bot`)
- Pod/image table (`post-deploy-validator`)
- Cluster time of report

Do not invent passing checks. If a check was skipped, mark `not run`.

## Output Format

Write `/sandbox/output/release/handover-YYYY-MM-DD-HHmm.md`:

```
# Release handover — {app} — {timestamp}

## Components deployed
| Component | Image | Namespace | Source PR |
|-----------|-------|-----------|-----------|

## Checks executed
| Check | Result | Evidence |
|-------|--------|----------|
| YAML / pin review | pass/fail/not run | |
| Post-deploy pods | pass/fail/not run | |
| Post-deploy image | pass/fail/not run | |

## Environment status
- Cluster / project: { }
- Unhealthy pods in namespace: {n} (names if any)
- Overall: ready for handover | blocked

## Residual risk
- {bullet or "none noted"}
```

Keep it short enough for AppOps and ADM. No secrets, no full logs.

## Safety

Tier 1. Do not merge, deploy, or page anyone unless `ESCALATION_WEBHOOK_URL`
is set **and** the user asked to notify (Tier 2).
