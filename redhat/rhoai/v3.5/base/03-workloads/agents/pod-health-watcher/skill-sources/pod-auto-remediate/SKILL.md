---
name: pod-auto-remediate
description: "Apply known-safe pod recovery under the 3-tier safety model. Default is confirm-then-act."
version: 1.0.0
author: AgentHive Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [Kubernetes, OpenShift, SRE, Remediation, Safety]
---

# Pod Auto-Remediate

Recover an unhealthy pod only when diagnosis says the action is safe. Most writes are Tier 2 (human confirmation). A narrow set of controller-managed recreates is Tier 3 (pre-approved).

## Trigger Phrases

- "Restart that pod"
- "Delete the stuck pod so it recreates"
- Invoked by `pod-health-watcher` after a known-safe diagnosis

## Required MCP Tools

| MCP Server | Tool | Purpose |
|---|---|---|
| mcp_openshift | pods_get | Re-check owner, phase, and deletionTimestamp immediately before acting |
| mcp_openshift | pods_delete | Delete a pod so its controller recreates it |
| mcp_openshift | resources_get | Confirm owner still exists and is not paused/scaled to 0 |
| mcp_openshift | events_list | Verify recovery after the action |

## Known-Safe Patterns (Tier 3 — no extra confirmation)

All of the following must be true:

1. Diagnosis class is one of: `init-stuck`, `failed-recreate`, `terminating-stuck`
2. Owner kind is Deployment, ReplicaSet, StatefulSet, or DaemonSet
3. Namespace is **not** protected
4. Owner still exists and desired replicas > 0
5. This workload (`namespace/owner`) has been auto-remediated fewer than 2 times in the last 30 minutes (check MEMORY.md)

Allowed action: `mcp_openshift_pods_delete` on that single pod. Nothing else.

## Always Tier 2 (ask first)

- CrashLoopBackOff, OOMKilled, ImagePullBackOff, config-error, probe-fail
- Rollout restart of a Deployment
- Scale up/down
- Any pod with no controller owner
- Job or CronJob pods
- Any write in a protected namespace (and the correct answer is usually **refuse + escalate**)

## Protected Namespaces (never mutate)

`openshift-*`, `kube-*`, `default`, `redhat-ods-*`, `openshift-gitops`, `sealed-secrets`, `mcp-*`

## Procedure

1. Re-read the diagnosis. If class is not known-safe, stop and load `incident-escalator`.
2. Call `mcp_openshift_pods_get` again. Abort if the pod is already Running/Ready.
3. Call `mcp_openshift_resources_get` on the owner. Abort if missing or replicas=0.
4. Check MEMORY.md cooldown. If already remediated twice in 30 minutes → escalate (possible crash loop).
5. If Tier 3: delete the pod. If Tier 2: present the plan and **wait for confirmation**.
6. Wait ~20 seconds. Call `pods_list_in_namespace` and `events_list` to see the replacement.
7. Record the attempt in MEMORY.md: time, namespace, pod, owner, action, result.
8. If the replacement is still unhealthy → do not delete again. Load `incident-escalator`.

## Remediation Plan (always show before Tier 2; show after for Tier 3)

```
# Remediation — {namespace}/{pod}

- **Class**: {class}
- **Action**: delete pod (controller {kind}/{name} will recreate)
- **Tier**: 2 (confirm) | 3 (pre-approved)
- **Blast radius**: one replica; others remain
- **Rollback**: none needed; new pod is equivalent spec
- **Cooldown**: {prior attempts in 30m}
```

## After Action

```
# Remediation Result — {timestamp}

- Deleted: {namespace}/{pod}
- Replacement: {new-pod} phase={phase} ready={bool}
- Events: {Scheduled / Pulled / Started / Warning}
- Outcome: recovered | still-unhealthy (escalated)
```

## Safety Constraints

- One pod per invocation. Never delete a list of pods in a loop without per-pod checks.
- Never `resources_delete` on a Deployment, namespace, or PVC.
- Never patch images, env, or resource limits.
- If MCP returns 403 on delete, treat as no-write. Report the exact `oc delete pod` command and escalate — do not retry via other channels.
- ImagePullBackOff and OOMKilled are never auto-deleted; deletion will not fix the image or the memory limit.
