# PR Review Bot

Generates deploy YAML, reviews release PRs, validates pods/images after sync, and writes handover reports. Built on the AgentHive platform.

## Skills

| `release-yaml-generator` | See skill-sources/release-yaml-generator/SKILL.md |
| `pr-review-bot` | See skill-sources/pr-review-bot/SKILL.md |
| `post-deploy-validator` | See skill-sources/post-deploy-validator/SKILL.md |
| `gitops-merge-manager` | See skill-sources/gitops-merge-manager/SKILL.md |
| `release-handover-report` | See skill-sources/release-handover-report/SKILL.md |

## Safety model

| Tier | Mode | Examples |
|---|---|---|
| 1 | Read-only (autonomous) | Scan, classify, review, report |
| 2 | Confirmed write | Open PR, merge, rollout restart |
| 3 | Pre-approved autonomy | Narrow GitOps PR or comment-only review |

Protected namespaces (`openshift-*`, `kube-*`, `redhat-ods-*`) are observe-only.

## Cluster access

OpenShift MCP: `http://openshift-mcp-v2.openshift-mcp-server.svc.cluster.local:8080/mcp`

GitHub MCP (optional PAT in `pr-review-bot-auth` key `github-token`): npx `@modelcontextprotocol/server-github`

## GitOps rollout

Push to `main`. ArgoCD syncs the Application and a PostSync Job deletes the
sandbox pod so the controller recreates it with the new ConfigMaps. Cron is
registered by `startup.sh` on every pod start (`every 15m`).

Do not `oc patch` the Sandbox. `spec.operatingMode` stays `Running` in git.
