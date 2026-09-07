# Example: Platform Health Check

A simple example showing how the agent responds to a platform health inquiry.

## User Prompt

> "Give me the full platform health status"

## Expected Agent Behavior

1. Calls `list_applications` (ArgoCD MCP) to get all applications
2. Calls `cluster_summary` (RHOAI MCP) for platform overview
3. Compiles results into a structured health report

## Sample Output

```
Platform Health Report — 2024-12-15T08:00Z

ArgoCD Applications (12 total):
  ✓ Healthy & Synced: 10
  ⚠ OutOfSync: 1 (gpu-operator — startingCSV drift)
  ✗ Degraded: 1 (rhoai-instance — workbench pod CrashLoopBackOff)

RHOAI Components:
  ✓ Dashboard: Running
  ✓ KServe: Running
  ✓ ModelRegistry: Running
  ⚠ Workbenches: 1 pod unhealthy

Recommendation:
  - gpu-operator: Add /spec/startingCSV to ignoreDifferences
  - rhoai-instance: Check workbench pod logs for OOM or image issues
```
