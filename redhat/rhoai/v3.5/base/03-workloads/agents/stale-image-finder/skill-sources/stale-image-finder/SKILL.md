---
name: stale-image-finder
description: "Cron-driven inventory of container images across namespaces, with age and pin-status for 30/60/90-day compliance."
version: 1.0.0
author: AgentHive Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [Kubernetes, OpenShift, SRE, Images, Compliance, Cron]
---

# Stale Image Finder

Scan the cluster for container images that are past MetLife-style 30/60/90-day
refresh windows, unpinned (`:latest`), or drifting from GitOps. Designed for
Hermes cron every 6 hours and on-demand namespace checks.

## Trigger Phrases

- "Find stale images"
- "Which images are past 90 days?"
- "Image compliance report"
- "Scan images in namespace X"
- Scheduled: every 6 hours via `hermes cron`

## Scheduled Trigger

```
hermes cron create --name stale-image-scan --skill stale-image-finder --continuity "every 6h" "Run the stale-image-finder skill."
```

## Required MCP Tools

| MCP Server | Tool | Purpose |
|---|---|---|
| mcp_openshift | namespaces_list | Discover namespaces |
| mcp_openshift | pods_list / pods_list_in_namespace | Running images per pod |
| mcp_openshift | pods_get | image, imageID, startedAt, owners |
| mcp_openshift | resources_list / resources_get | Deployment/StatefulSet desired image |

Optional: Artifactory REST (`ARTIFACTORY_URL`) for catalog created-date.
This demo cluster has no MetLife Artifactory — use pod `startedAt` plus
image pin-status as the age signal, and say so in the report.

Optional: GitHub MCP to locate GitOps YAML that pins the image.

## Age Signal (demo vs production)

**Demo (this cluster):**

1. For each container: `image`, `imageID` (digest if present), `startedAt`.
2. Age = now minus `startedAt` of the oldest pod running that image:digest.
3. Flag `:latest`, empty tag, or missing digest as **unpinned** (immediate stale).

**Production (MetLife Artifactory):**

1. Resolve the image to an Artifactory item.
2. Age = now minus artifact `created` / `lastModified`.
3. Latest eligible tag = Artifactory latest within the compliance window.

Do not invent Artifactory results. If `ARTIFACTORY_URL` is unset, label the
report `source: cluster-runtime` and continue.

## Procedure

### Phase 1: Scope

1. If the user named a namespace, scan only that namespace.
2. Otherwise call `mcp_openshift_namespaces_list`.
3. Observe protected namespaces but never propose mutations there:
   `openshift-*`, `kube-*`, `default`, `redhat-ods-*`, `openshift-gitops`,
   `sealed-secrets`, `mcp-*`.

### Phase 2: Inventory

4. For each in-scope namespace, list pods and record unique
   `(namespace, workload, container, image, imageID, startedAt, owner)`.
5. Group by image reference (repo + tag or digest).
6. Note workloads whose pod image differs from the owner spec image (drift).

### Phase 3: Route

7. Load `image-compliance-classifier` to bucket 30/60/90 and severity.
8. If any red/orange (or unpinned) images exist in non-protected namespaces,
   load `image-refresh-pr` to propose GitOps bumps (do not merge).
9. After a merged bump or user-confirmed sync, load `image-rebuild-redeploy`
   to verify the new image is running.

### Phase 4: Persist

10. Write both `/sandbox/output/images/latest.md` (overwrite) and
    `/sandbox/output/images/YYYY-MM-DD-HHmm.md` using the file-write tool
    (not execute_code).
11. Update MEMORY.md with counts and the top stale images (no digests of
    private registries beyond the repo/name:tag already on the pod).

When the user asks for the last scan or cron output: read `latest.md`,
else the newest `/sandbox/.hermes/cron/output/*/*.md` `## Response` section.
Never treat an empty `images/` dir as "nothing stale" if cron files exist.

## Output Format

```
# Stale Image Report — {timestamp}

## Summary
- Namespaces scanned: {n}
- Unique images: {n}
- Unpinned: {n} | 30d: {n} | 60d: {n} | 90d+: {n}
- Source: cluster-runtime | artifactory
Overall: {healthy | degraded | failed}

## Stale / Unpinned
| Namespace | Workload | Image | Age | Window | Next step |
|-----------|----------|-------|-----|--------|-----------|
| {ns} | {kind/name} | {image} | {age} | 30/60/90/unpinned | classify / PR / verify |
```

When everything is inside 30 days and pinned, write the healthy latest.md
then mark `[SILENT]` on cron only. If anything is unpinned or past 30 days,
do not `[SILENT]`.

## Safety Constraints

- This skill is Tier 1 (read-only). Do not patch workloads, push git, or merge.
- Do not print registry credentials or full `imagePullSecret` values.
- Cron runs stay quiet when healthy (`[SILENT]`).
