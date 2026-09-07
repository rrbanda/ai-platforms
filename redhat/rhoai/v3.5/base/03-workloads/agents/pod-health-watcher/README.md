# Pod Health Watcher

An AI agent that monitors Kubernetes pods for Init/Failed states, diagnoses root cause, and triggers safe automatic recovery. Built on the AgentHive platform.

## What it does

| Capability | Description |
|---|---|
| Scheduled scanning | Hermes cron every 5 minutes across watched namespaces |
| Failure diagnosis | Classifies CrashLoop, ImagePull, OOM, Init, Pending, probe, and node issues from events and logs |
| Safe auto-recovery | Deletes controller-managed pods stuck in known-safe failure states so the controller recreates them |
| Escalation | Severity-based incident reports to AppOps (webhook or local incident file) |
| 3-tier safety | Read-only by default; mutating actions require confirmation except pre-approved patterns |

## Skills

| Skill | Purpose |
|---|---|
| `pod-health-watcher` | Cron-driven scan for unhealthy pods |
| `pod-failure-diagnoser` | Analyze events/logs and classify the failure |
| `pod-auto-remediate` | Apply known-safe recovery with the 3-tier gate |
| `incident-escalator` | Notify AppOps and record the incident |

## Safety model

| Tier | Mode | Examples |
|---|---|---|
| 1 | Read-only (autonomous) | List pods, events, logs; health reports |
| 2 | Confirmed write | Delete a pod, rollout restart, scale |
| 3 | Pre-approved autonomy | Recreate a Deployment-managed pod stuck in Init/Failed |

Protected namespaces (`openshift-*`, `kube-*`, `redhat-ods-*`) are diagnose-and-escalate only — never mutated.

## Cluster access

Uses the cluster OpenShift MCP server:

`http://openshift-mcp-v2.openshift-mcp-server.svc.cluster.local:8080/mcp`

## Reports

Every scan must write `/sandbox/output/health/latest.md`. Hermes also stores
raw cron transcripts under `/sandbox/.hermes/cron/output/`. If the dashboard
asks for the last run, the agent reads `latest.md` first, then cron output.
An empty `health/` directory is not proof the cluster is healthy.

## GitOps rollout

Push to `main`. ArgoCD syncs the Application and a PostSync Job deletes the sandbox pod so the controller recreates it with the new ConfigMaps (startup, soul, skills, config). The 5-minute Hermes cron is registered by `startup.sh` on every pod start.

Do not `oc patch` the Sandbox. `spec.operatingMode` stays `Running` in git.
