---
name: release-yaml-generator
description: "Create or update deployment YAML for a release PR (pre-deploy GitOps artifacts)."
version: 1.0.0
author: AgentHive Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [GitOps, YAML, Release, Pre-deploy]
---

# Release YAML Generator

Pre-deployment: produce or update Kubernetes/OpenShift YAML (Deployment,
Kustomize, ArgoCD Application, image pin) so a human or `pr-review-bot`
can open a PR. Matches MetLife "create deployment yaml files".

## Trigger Phrases

- "Generate deploy YAML for X"
- "Prepare a release PR for image Y"
- "Scaffold a kustomize overlay"

## Required MCP Tools

| MCP Server | Tool | Purpose |
|---|---|---|
| mcp_github | get_file_contents | Clone existing pattern |
| mcp_github | search_code | Find similar manifests |
| mcp_openshift | resources_get | Optional: current live spec to copy |

## Procedure

1. Identify target: namespace, workload name, image, repo (`GITOPS_REPO`).
2. Prefer copying an existing in-repo pattern (`agents/pod-health-watcher`
   or `agents/rfp-agent`) over inventing CRDs.
3. Emit files under `/sandbox/output/release/{app}/` first.
4. Validate mentally: name, namespace, image pin (tag or digest, not
   `:latest` unless the user insists), probes, non-root if the pattern
   allows. Do not weaken securityContext compared to the template.
5. Hand off to `pr-review-bot` to open the PR, or to GitHub MCP after
   Tier 2 confirmation.

## Must Never

- Write live cluster objects (`oc apply`) from this skill.
- Embed secrets; use SealedSecret placeholders only.
- Invent APIs that are not in the copied template.

## Output

File list, image pin, namespace, and next skill `pr-review-bot`.
