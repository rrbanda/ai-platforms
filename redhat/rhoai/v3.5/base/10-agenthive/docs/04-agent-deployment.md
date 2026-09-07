# 04 — Agent deployment (add a new agent)

This is the required procedure. The root README summary links here.

## Pick a starting point

| Kind of agent | Copy |
|---------------|------|
| Ops / MCP / cron | `platform/sandbox-template/` (same shape as `agents/pod-health-watcher/`) |
| RAG + corpus + EvalHub | `agents/rfp-agent/` |
| Large RHOAI lifecycle | Do not copy `rhoai-copilot` as a blank slate; copy the template and add skills |

```bash
cp -r platform/sandbox-template agents/my-agent
# Rename every example-agent occurrence (namespace, Sandbox, Route, ConfigMaps, SKILLS).
```

## Agent package (inside `agents/my-agent/`)

These files must exist and stay consistent:

| File | Role |
|------|------|
| `sandbox.yaml` | Sandbox CR, env, skill volume mounts, image |
| `startup.yaml` | `SKILLS=` list; copies mounts into Hermes; optional cron |
| `soul.yaml` / `config.yaml` | Personality and model/MCP |
| `policy.yaml` + `sandbox-policy.rego` | OpenShell allowlists |
| `skill-sources/<skill>/SKILL.md` | Authoring source |
| `skills/skill-<skill>.yaml` | Deployed ConfigMap (`data.SKILL.md`) |
| `kustomization.yaml` | Lists every skill ConfigMap |
| `service.yaml` / `route.yaml` | Dashboard |
| `restart-hook.yaml` | PostSync **delete pod** (never patch `operatingMode`) |
| `restart-rbac.yaml` | Role `pods/delete` for the restart Job |

Keep these four lists identical: skill-sources names, `skills/*.yaml`, kustomization resources, sandbox mounts, `startup.sh` `SKILLS=`.

```bash
python3 platform/scripts/sync-skills.py --agent my-agent
python3 platform/scripts/check-skill-parity.py
```

## Platform wiring (outside the agent dir)

Git push does nothing until all of these exist:

1. **ArgoCD Application** — copy `platform/gitops/apps/pod-health-watcher.yaml` to `platform/gitops/apps/my-agent.yaml`. Set `metadata.name`, `spec.source.path: agents/my-agent`, `spec.destination.namespace`.
2. **Register the app** — add the file to `platform/gitops/apps/kustomization.yaml` `resources:` and add `REPO_URL` / `REPO_BRANCH` replacements for that Application name (same pattern as the other agents).
3. **ServiceAccount + privileged SCC** — add Namespace, `openshell-sandbox` SA, and ClusterRoleBinding to `system:openshift:scc:privileged` in `platform/gitops/infra/rbac/openshell-sandbox-sa.yaml`. Copy the `pod-health-watcher` block. Do not remove privileged SCC; see [01-cluster-prerequisites.md](01-cluster-prerequisites.md).
4. **Restart ClusterRoleBinding** — add a subject in `platform/gitops/infra/rbac/sandbox-restart-role.yaml` for `openshell-sandbox` in the new namespace (needed if anything still gets Sandbox get/list).
5. **Sealed secrets** — extend `platform/gitops/secrets/seal-secrets.sh` and `kustomization.yaml` with `my-agent-auth` (`llm-api-key`, `dashboard-password`, `api-server-key`). Add OpenShell TLS SealedSecret for the namespace if the three ops agents’ TLS files are the pattern you follow.
6. **MCP NetworkPolicy** — if the agent uses OpenShift MCP, add its namespace to `platform/mcp-servers/openshift/networkpolicy.yaml` ingress.
7. **Image** — Sandboxes currently use `ghcr.io/rrbanda/rfp-agent:latest`. Pin a digest or tag in git before production promote; CD (`cd-deploy.yaml`) can set the rfp-agent image tag.

## Use the agent

```bash
echo "https://$(oc get route my-agent -n my-agent -o jsonpath='{.spec.host}')"
```

Log in with dashboard basic auth from the auth secret. After a git sync, the PostSync Job deletes the sandbox pod so ConfigMaps remount. Do not `oc patch` `spec.operatingMode`.
