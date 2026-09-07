---
name: daily-report-generator
description: "Generate automated daily/weekly platform health summaries — designed for cron scheduling and stakeholder communication."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, SRE, Daily Report, Health Summary, Cron, Automation]
---

# Daily Report Generator

Generates comprehensive platform health summaries suitable for automated daily/weekly scheduling via Hermes cron and stakeholder communication.

## Trigger Phrases

- "Generate daily report"
- "Platform health summary"
- "Morning status report"
- "Weekly platform report"
- "Executive summary of RHOAI status"

## Scheduled Triggers (Cron)

This skill is designed to be run automatically:
- **Daily 8:00 AM**: Full health report
- **Weekly Monday 9:00 AM**: Extended weekly digest with trends

Setup: `hermes cronjob create --schedule "0 8 * * *" --prompt "Generate the daily RHOAI platform health report using the daily-report-generator skill"`

## Procedure

### Phase 1: Platform Health Summary

1. Call `mcp_argocd_list_applications` to get all application statuses:
   - Count: total, healthy, degraded, missing, progressing
   - Identify any that changed since last report
2. Call `mcp_rhoai_cluster_summary` for DSC and component status
3. Call `mcp_openshift_nodes_top` for node-level resource usage

### Phase 2: Workload Status

4. Call `mcp_rhoai_list_inference_services` for model serving status:
   - Total models deployed
   - Models in Ready state
   - Models in error state
   - Any new deployments since last report
5. Call `mcp_rhoai_list_workbenches` for notebook status:
   - Active workbenches
   - Idle workbenches (candidates for culling)
   - Failed workbenches
6. Call `mcp_rhoai_list_data_science_projects` for project overview:
   - Total projects
   - Active projects (with recent activity)

### Phase 3: Resource Utilization

7. Call `mcp_openshift_nodes_top` for resource metrics:
   - Average CPU utilization across nodes
   - Average memory utilization
   - GPU allocation rate
8. Identify resource pressure:
   - Nodes above 80% CPU/memory
   - GPU fully allocated (no spare capacity)
   - Any nodes in NotReady state

### Phase 4: GitOps Drift Detection

9. Call `mcp_argocd_list_applications` and check for:
   - OutOfSync applications (Git differs from live state)
   - Failed sync attempts
   - Applications with `ComparisonError` (unreachable Git)
10. For any drifted applications:
    - Call `mcp_argocd_get_application` to identify the drift details
    - Note if drift is expected (pending PR) or unexpected

### Phase 5: Alerts and Issues

11. Call `mcp_openshift_events_list` with type=`Warning` for the last 24h:
    - Cluster-level warnings
    - RHOAI namespace warnings
12. Compile issues requiring attention:
    - Any P1/P2 items from the last 24h
    - Pending operator upgrades
    - Certificate expiration warnings
    - Quota approaching limits

### Phase 6: Generate Report

13. Compile all findings into the structured report format below

## Output Format

```
# RHOAI Platform Report — {date}

## Executive Summary
{2-3 sentence overall status}
Overall Health: {🟢 Healthy | 🟡 Warning | 🔴 Critical}

## Platform Health
| Category | Status | Count | Issues |
|----------|--------|-------|--------|
| ArgoCD Applications | 🟢/🟡/🔴 | {healthy}/{total} | {issues} |
| Operators | 🟢/🟡/🔴 | {healthy}/{total} | {issues} |
| Models Serving | 🟢/🟡/🔴 | {ready}/{total} | {issues} |
| Workbenches | 🟢/🟡/🔴 | {active}/{total} | {issues} |
| Nodes | 🟢/🟡/🔴 | {ready}/{total} | {issues} |

## Resource Utilization
| Resource | Usage | Capacity | Utilization | Trend |
|----------|-------|----------|-------------|-------|
| CPU | {used} | {total} | {pct}% | ↑/→/↓ |
| Memory | {used} | {total} | {pct}% | ↑/→/↓ |
| GPU | {alloc}/{total} | {total} | {pct}% | ↑/→/↓ |
| Storage | {used} | {total} | {pct}% | ↑/→/↓ |

## GitOps Status
| Application | Sync | Health | Last Sync |
|-------------|------|--------|-----------|
| {app_name} | Synced/OutOfSync | Healthy/Degraded | {time} |

**Drifted**: {count} applications out of sync
**Failed syncs**: {count} in last 24h

## Active Workloads
### Model Serving ({count} models)
| Model | Namespace | Runtime | Status | GPUs |
|-------|-----------|---------|--------|------|
| {name} | {ns} | {runtime} | Ready/Error | {n} |

### Training Jobs ({count} active)
| Job | Namespace | GPUs | Duration | Progress |
|-----|-----------|------|----------|----------|
| {name} | {ns} | {n} | {time} | {pct}% |

### Workbenches ({active} active / {idle} idle)
| Workbench | Namespace | GPU | Last Activity | Status |
|-----------|-----------|-----|---------------|--------|
| {name} | {ns} | {y/n} | {time} | Active/Idle |

## Alerts & Issues
### Critical (P1-P2)
{List or "None"}

### Warnings
| Source | Message | Since |
|--------|---------|-------|
| {source} | {message} | {time} |

### Upcoming
- Operator upgrades pending: {list}
- Certificate renewals: {list}
- Quota approaching: {list}

## Recommendations
1. {Priority 1 recommendation}
2. {Priority 2 recommendation}
3. {Priority 3 recommendation}

---
*Report generated by Hermes RHOAI Agent at {timestamp}*
*Next report: {next_scheduled_time}*
```

## Weekly Extension (Monday only)

For weekly reports, append:

```
## Weekly Trends
| Metric | Last Week | This Week | Change |
|--------|-----------|-----------|--------|
| Models deployed | {n} | {n} | +{n} |
| Training jobs completed | {n} | {n} | +{n} |
| Active users | {n} | {n} | +{n} |
| GPU utilization avg | {pct}% | {pct}% | +{pct}% |
| Incidents (P1-P2) | {n} | {n} | +{n} |

## Week in Review
- New models deployed: {list}
- Completed training: {list}
- Resolved incidents: {list}
- Configuration changes: {list of ArgoCD syncs}

## Next Week Outlook
- Planned maintenance: {list}
- Expected deployments: {list}
- Resource concerns: {list}
```

## Domain Knowledge

- Reports should be concise and actionable — executives want status, SREs want details
- GPU utilization trends are the #1 capacity signal for AI platforms
- OutOfSync applications in GitOps indicate either pending changes or drift — distinguish between them
- Idle workbench detection: no kernel activity for >4 hours = candidate for culling
- Certificate expiration warnings should be raised 14+ days before expiry
- ArgoCD ApplicationSets manage operator and instance lifecycle — check the AppSet health too
