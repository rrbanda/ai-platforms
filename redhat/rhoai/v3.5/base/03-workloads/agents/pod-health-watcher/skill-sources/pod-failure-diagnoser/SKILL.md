---
name: pod-failure-diagnoser
description: "Classify why a Kubernetes pod is unhealthy using OpenShift MCP events and logs."
version: 1.0.0
author: AgentHive Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [Kubernetes, OpenShift, SRE, Diagnostics, Logs, Events]
---

# Pod Failure Diagnoser

Determine the failure class of an unhealthy pod from spec, events, and logs. Does not mutate the cluster.

## Trigger Phrases

- "Why is pod X failing?"
- "Diagnose CrashLoop / ImagePull / Init error"
- Invoked by `pod-health-watcher` after a scan finds unhealthy pods

## Required MCP Tools

| MCP Server | Tool | Purpose |
|---|---|---|
| mcp_openshift | pods_get | Spec, status, ownerRefs, container states, exit codes |
| mcp_openshift | events_list | Warning events for the pod/namespace |
| mcp_openshift | pods_log | Last 100 lines of app and init containers |
| mcp_openshift | resources_get | Owner (Deployment, ReplicaSet, Job, StatefulSet) |
| mcp_openshift | nodes_top | Node pressure when the pod is Pending |

## Failure Classes

| Class | Signals | Safe auto-remediate? |
|-------|---------|----------------------|
| `init-stuck` | Init container waiting/error > 5 min, owner is Deployment/RS/SS/DS | Yes (Tier 3) if controller-managed |
| `failed-recreate` | Phase Failed, controller will recreate | Yes (Tier 3) if controller-managed |
| `terminating-stuck` | deletionTimestamp > 5 min | Yes (Tier 3) if controller-managed |
| `crashloop` | CrashLoopBackOff, non-zero exit, app logs show exception | No — needs code/config |
| `oomkilled` | Last state OOMKilled, exit 137 | No — needs memory limit change |
| `image-pull` | ImagePullBackOff / ErrImagePull | No — needs image/registry fix |
| `config-error` | CreateContainerConfigError, missing secret/configmap | No — needs manifest fix |
| `pending-resource` | Pending, events: Insufficient cpu/memory/gpu | No — needs capacity |
| `pending-schedule` | Pending, taints, affinity, PVC, SCC | No — needs schedule/policy fix |
| `probe-fail` | Restart from failed liveness/readiness | No — needs probe/app fix |
| `evicted` | Reason Evicted, node disk/memory pressure | Escalate; recreate only if controller-managed and node recovered |
| `node-issue` | Node NotReady, network unavailable | Escalate |
| `unknown` | No matching class | Escalate |

## Procedure

1. Call `mcp_openshift_pods_get` for the pod. Record:
   - phase, podIP, nodeName, startTime, deletionTimestamp
   - ownerReferences (kind, name)
   - each container: ready, restartCount, waiting.reason, terminated.reason, exitCode, lastState
2. Call `mcp_openshift_events_list` for the namespace. Keep Warning/Error events whose `involvedObject.name` is this pod. Note `reason` and `message`.
3. Call `mcp_openshift_pods_log` for the failing container (last 100 lines). If an init container failed, log that init container too. Redact tokens and passwords.
4. If phase is Pending, call `mcp_openshift_nodes_top` and check Insufficient/taint events.
5. If an owner exists, call `mcp_openshift_resources_get` for that owner to confirm it will recreate a replacement.
6. Assign exactly one Failure Class from the table. Prefer the most specific match.
7. Recommend the next skill:
   - known-safe class + allowed owner + non-protected namespace → `pod-auto-remediate`
   - otherwise → `incident-escalator`

## Output Format

```
# Diagnosis — {namespace}/{pod} — {timestamp}

## Classification
- **Class**: {class}
- **Severity**: P{1-4}
- **Owner**: {kind}/{name} or none
- **Controller recreates?**: yes/no
- **Protected namespace?**: yes/no
- **Next step**: remediate | escalate | observe

## Evidence
- Phase: {phase} | Ready: {bool} | Restarts: {n} | Node: {node}
- Waiting/terminated: {reason} exit={code}
- Events:
  | Time | Reason | Message |
  |------|--------|---------|
  | {t} | {reason} | {message} |
- Logs (excerpt, redacted):
  {last relevant lines}

## Root cause
{one paragraph grounded in the evidence}

## Recommended action
{specific next step and why it is or is not auto-safe}
```

## Severity

| Severity | When |
|----------|------|
| P1 | Many pods down in a production namespace, or a protected-namespace control plane pod Failed |
| P2 | Single production Deployment unavailable (0 ready replicas) |
| P3 | One replica of a multi-replica workload, or non-prod |
| P4 | Transient Pending < 10 min with a clear scheduler retry |

## Safety Constraints

- Tier 1 only. No deletes, patches, or exec.
- Never print Secret data if a log line looks like a key or token — replace with `[REDACTED]`.
- Do not blame "the node" without node or event evidence.
