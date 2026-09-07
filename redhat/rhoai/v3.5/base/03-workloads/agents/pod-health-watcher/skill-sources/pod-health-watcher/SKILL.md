---
name: pod-health-watcher
description: "Cron-driven scan for unhealthy Kubernetes pods — Init, Failed, CrashLoop, ImagePull, Pending, Terminating."
version: 1.1.0
author: AgentHive Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [Kubernetes, OpenShift, SRE, Pod Health, Monitoring, Cron]
---

# Pod Health Watcher

Scan the cluster for pods that are not healthy. Designed for Hermes cron every
5 minutes and for on-demand namespace checks.

## Trigger Phrases

- "Check pod health"
- "Scan for failing pods"
- "Any pods in CrashLoop / Init / Failed?"
- "Health report for namespace X"
- "Did the scheduled job run?" / "Show the last scan" / "Show last cron output"
- Scheduled: every 5 minutes via `hermes cron`

## Scheduled Trigger

```
hermes cron create --name pod-health-scan --skill pod-health-watcher --continuity "every 5m" "Run the pod-health-watcher skill."
```

## Required MCP Tools

| MCP Server | Tool | Purpose |
|---|---|---|
| mcp_openshift | namespaces_list | Discover namespaces to scan |
| mcp_openshift | pods_list / pods_list_in_namespace | List pods and container statuses |
| mcp_openshift | pods_get | Confirm phase, ready, owner, start time |

## Unhealthy Signals

A pod is unhealthy if any of the following is true:

- Phase is `Failed` or `Unknown`
- Waiting reason is `CrashLoopBackOff`, `ImagePullBackOff`, `ErrImagePull`, `CreateContainerConfigError`, `CreateContainerError`, `InvalidImageName`
- An init container is in error (`Init:Error`, `Init:CrashLoopBackOff`)
- Phase is `Pending` or reason is `ContainerCreating` for more than 5 minutes
- Deletion timestamp set (Terminating) for more than 5 minutes
- Last termination reason is `OOMKilled` or `Evicted`
- Ready=False for a controller-managed pod that should be Ready

## Showing the last scheduled run (interactive)

When the user asks whether cron ran, to see the last output, or for the
latest health report, do this in order. Do **not** start a full cluster
rescan unless they ask for a fresh scan.

1. `hermes cron list` and `hermes cron runs` (terminal) — prove last run time and status.
2. Read `/sandbox/output/health/latest.md` if it exists. Quote the Summary and Unhealthy table (collapsed form).
3. If `latest.md` is missing, read the newest file under
   `/sandbox/.hermes/cron/output/*/`. Use only the `## Response` section
   (ignore the repeated skill prompt).
4. Never say you cannot show cron output. Never treat an empty
   `/sandbox/output/health/` as "all healthy" if cron output files exist.

## Persist rules (mandatory, cron and interactive)

Write reports with the **file write** tool (`write_file` / file_operations).
Do **not** use `execute_code` / Python to create report files.

Before the final chat/cron reply, always write both:

- `/sandbox/output/health/latest.md` (overwrite)
- `/sandbox/output/health/YYYY-MM-DD-HHmm.md` (archive)

Then, and only then, produce the user-visible reply.

Hermes `[SILENT]` is **delivery only**, and only when **all** of these are true:

- `latest.md` was just written
- Overall is `healthy`
- Unhealthy count is 0

If overall is `degraded` or `failed`, the final reply **must** be the
Summary (not `[SILENT]`), even if findings match the previous run. Keep it
short and point at `latest.md`.

## Collapse duplicates

Do not list 50 Job pods that share an owner prefix as 50 incidents.

Group by `(namespace, owner kind/name or CronJob/Job prefix, reason)`.
Example: 58 `maas-api-dns-patch-*` Job pods with ImagePullBackOff in
`redhat-ods-applications` → **one row** with `count=58`.

Protected namespaces remain observe + escalate only (no auto-delete).

## Procedure

### Phase 1: Scope

1. If the user named a namespace, scan only that namespace.
2. If they asked for the last report / last cron output, follow
   **Showing the last scheduled run** and stop unless they also asked to rescan.
3. Otherwise call `mcp_openshift_namespaces_list`.
4. Observe protected namespaces but never mutate them:
   `openshift-*`, `kube-*`, `default`, `redhat-ods-*`, `openshift-gitops`,
   `sealed-secrets`, `mcp-*`.

### Phase 2: Scan

5. For each in-scope namespace, call `mcp_openshift_pods_list_in_namespace`.
6. For each pod, record: name, namespace, phase, ready, restarts,
   waiting/terminated reason, startTime, owner kind/name.
7. Flag Unhealthy Signals. Collapse duplicates as above.

### Phase 3: Route

8. If **zero** unhealthy pods: persist a healthy `latest.md`, then `[SILENT]`
   on cron. On an interactive session, say healthy and show the path.
9. If unhealthy pods exist:
   - Load `pod-failure-diagnoser` for new/changed groups (not every duplicate Job).
   - Load `pod-auto-remediate` only for known-safe patterns in non-protected namespaces.
   - Load `incident-escalator` for unknown classes, protected namespaces, P1/P2,
     or remediation failure. One incident per **group**, not per duplicate pod.

### Phase 4: Persist

10. Write `latest.md` and the timestamped archive (see Persist rules).
11. Update MEMORY.md with counts and one line per **group**.

## Output Format

```
# Pod Health Report — {timestamp}

## Summary
- Namespaces scanned: {n}
- Pods total: {n}
- Unhealthy pods: {n} | Unhealthy groups: {n}
- Remediated: {n} | Escalated groups: {n}
Overall: {healthy | degraded | failed}
Report: /sandbox/output/health/latest.md

## Unhealthy groups
| Namespace | Workload / prefix | Count | Phase/Reason | Age (oldest) | Next step |
|-----------|-------------------|-------|--------------|--------------|-----------|
| {ns} | {kind/name or prefix*} | {n} | {reason} | {age} | diagnose / remediate / escalate |
```

## Safety Constraints

- This skill is Tier 1 (read-only). It must not delete, patch, or scale.
- Do not dump full logs here — that belongs to `pod-failure-diagnoser`.
- Do not invent "all clear" when cron output or MCP shows unhealthy pods.
