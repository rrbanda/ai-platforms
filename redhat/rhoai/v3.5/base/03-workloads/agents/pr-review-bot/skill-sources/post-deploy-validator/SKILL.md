---
name: post-deploy-validator
description: "After a release merge, validate running image and pod status in the target namespace."
version: 1.0.0
author: AgentHive Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [OpenShift, Release, Post-deploy, Validation]
---

# Post-Deploy Validator

MetLife "post deployment image and pod status validations". Read-only
cluster checks after GitOps sync.

## Trigger Phrases

- "Validate the deploy in namespace X"
- "Did pods come up with the new image?"
- Loaded after merge or on handover

## Required MCP Tools

| MCP Server | Tool | Purpose |
|---|---|---|
| mcp_openshift | pods_list_in_namespace | Ready / phase / restarts |
| mcp_openshift | pods_get | image vs expected |
| mcp_openshift | events_list | Warnings after sync |
| mcp_openshift | resources_get | Deployment/Sandbox desired spec |

## Procedure

1. Namespace + expected image from the PR or the user.
2. All app pods Ready 1/1 (or stated replica count). Init not stuck.
3. Running `image` / `imageID` matches expected pin.
4. No ImagePullBackOff, CrashLoopBackOff, Failed, or long Pending.
5. Record timestamp, pod names, images, events (warning only).

If unhealthy: do not auto-delete. Point to Pod Health Watcher and include
event/log excerpts. Handover report should mark **blocked**.

## Safety

Tier 1 only. No rollout restart unless the user confirms (Tier 2) and
`gitops-merge-manager` is not a substitute for live patch.

## Output

Pass/fail table: pod, ready, image, reason. Saved under
`/sandbox/output/release/validate-YYYY-MM-DD-HHmm.md`.
