---
name: image-refresh-pr
description: "Open a GitOps pull request that bumps a stale container image to a newer pinned tag or digest."
version: 1.0.0
author: AgentHive Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [GitOps, GitHub, Images, Pull Request]
---

# Image Refresh PR

Propose an image bump in Git (never live-patch the cluster). This is how ADM
"updating images" is done on AgentHive: GitOps PR, not `oc set image`.

## Trigger Phrases

- "Open a PR to refresh this image"
- "Bump image X in GitOps"
- Loaded after classification for orange/red images

## Required MCP Tools

| MCP Server | Tool | Purpose |
|---|---|---|
| mcp_github | search_code | Find YAML that pins the image |
| mcp_github | get_file_contents | Read current manifest |
| mcp_github | create_branch | Branch from default |
| mcp_github | create_or_update_file / push_files | Write bump |
| mcp_github | create_pull_request | Open the PR |

If GitHub MCP is unavailable (`GITHUB_TOKEN` missing), stop after writing
a patch suggestion under `/sandbox/output/images/patches/` and tell the
user to add a PAT. Do not pretend a PR exists.

## Target repo

Default `GITOPS_REPO` = `rrbanda/ai-platforms` (this platform).
Only touch that repo unless the user names another and confirms.

## New image selection

1. Prefer a digest-pinned reference over a moving tag.
2. If Artifactory is configured, use the latest tag **inside** the 30-day
   window that the classifier named. Do not jump to an arbitrary `:latest`.
3. On this demo cluster, if no catalog exists, **do not invent a newer tag**.
   Open a PR only when the user (or a catalog lookup) supplies the target
   image. Otherwise file a "needs target tag" note in the report.

## Procedure

1. Confirm the image and the Git path (kustomization, Deployment, Sandbox).
2. Search the allowed repo for the current image string.
3. Explain the diff: old image, new image, files, blast radius (which
   agent/workload will roll).
4. **Tier 2:** wait for explicit confirmation unless Tier 3 applies.
5. Create branch `image-refresh/{workload}-{date}`.
6. Push the file change. Open PR. Do not merge.
7. Record PR URL in MEMORY.md and the image report.

## 3-Tier gate

### Tier 1

Search and draft the diff only.

### Tier 2 (default for writes)

Creating the branch/PR requires the user to confirm the exact image bump.

### Tier 3 (narrow)

Allowed without extra confirmation only when ALL are true:

- `IMAGE_AUTO_PR=true`
- Repo is the allowlisted `GITOPS_REPO`
- Path is not under a name containing `prod` or `production`
- Target image was supplied by catalog or the user, not guessed
- Same image has not had an auto-PR in the last 24 hours

Never auto-PR into protected cluster namespaces' live objects — Git only.

## Must Never

- `oc patch` / `oc set image` / edit a live Deployment
- Force-push or merge the PR
- Change unrelated YAML
- Put tokens in the PR body
- Target `openshift-*` / `kube-*` operand images

## Output

PR URL, files changed, old → new image, and "merge is human / merge-manager".
