# Example: Incident Response

Demonstrates the agent's incident response workflow when the platform is degraded.

## User Prompt

> "We're getting alerts — multiple applications are failing. What's going on?"

## Expected Agent Behavior

1. Calls `list_applications` to identify all unhealthy/out-of-sync apps
2. For each failing app, calls `get_application` + `get_application_resource_tree`
3. Checks pod-level events via OpenShift MCP
4. Produces a root-cause analysis with remediation steps

## Sample Output

```
Incident Triage Report

Affected Applications: 3/12

1. rhoai-operator (Degraded)
   Root Cause: CSV pending approval after upgrade
   Remediation: Approve InstallPlan in openshift-operators namespace

2. mlflow-instance (OutOfSync)
   Root Cause: Image tag changed in Git but not synced
   Remediation: Run `sync_application` (dry-run first)

3. gpu-operator (Progressing)
   Root Cause: DaemonSet rolling update in progress (3/5 nodes complete)
   Remediation: No action needed — will resolve in ~5 minutes

Overall Assessment: Non-critical. No data loss risk.
Estimated resolution: 15 minutes after manual approval of InstallPlan.
```
