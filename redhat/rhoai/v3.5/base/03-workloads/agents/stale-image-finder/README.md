# Stale Image Finder

Finds container images past 30/60/90-day windows and opens GitOps PRs to refresh them. Built on the AgentHive platform.

## Skills

| `stale-image-finder` | See skill-sources/stale-image-finder/SKILL.md |
| `image-compliance-classifier` | See skill-sources/image-compliance-classifier/SKILL.md |
| `image-refresh-pr` | See skill-sources/image-refresh-pr/SKILL.md |
| `image-rebuild-redeploy` | See skill-sources/image-rebuild-redeploy/SKILL.md |

## Safety model

| Tier | Mode | Examples |
|---|---|---|
| 1 | Read-only (autonomous) | Scan, classify, review, report |
| 2 | Confirmed write | Open PR, merge, rollout restart |
| 3 | Pre-approved autonomy | Narrow GitOps PR or comment-only review |

Protected namespaces (`openshift-*`, `kube-*`, `redhat-ods-*`) are observe-only.

## Cluster access

OpenShift MCP: `http://openshift-mcp-v2.openshift-mcp-server.svc.cluster.local:8080/mcp`

GitHub MCP (optional PAT in `stale-image-finder-auth` key `github-token`): npx `@modelcontextprotocol/server-github`

## GitOps rollout

Push to `main`. ArgoCD syncs the Application and a PostSync Job deletes the
sandbox pod so the controller recreates it with the new ConfigMaps. Cron is
registered by `startup.sh` on every pod start (`every 6h`).

Do not `oc patch` the Sandbox. `spec.operatingMode` stays `Running` in git.
