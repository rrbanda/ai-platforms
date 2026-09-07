# 06 — Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| rhoai-copilot starts with RFP skills | `startup.sh` `SKILLS=` must match `skills/` (fixed in tree; re-sync if you forked an old copy) |
| Sandbox CrashLoop, SCC denied | Missing `openshell-sandbox` SA or privileged SCC binding for that namespace |
| OpenShift MCP connection refused | Service DNS is `openshift-mcp-v2.openshift-mcp-server.svc.cluster.local:8080`. Application `openshift-mcp` must be Synced. |
| NetworkPolicy drop to MCP | Agent namespace not listed in `platform/mcp-servers/openshift/networkpolicy.yaml` |
| RAG empty / ingest uploaded 0 files | Corpus is `agents/rfp-agent/corpus/`, not `platform/corpus/` |
| ConfigMap change not visible in chat | Restart hook must delete the sandbox **pod**. Do not patch `operatingMode` (ArgoCD reverts it). |
| Dashboard 401 | `dashboard-password` on `*-auth` SealedSecret; bump `agenthive.io/dashboard-password-rev` if the pod cached the old secret |
| Open WebUI shows two `hermes-agent` models | Set unique `API_SERVER_MODEL_NAME` on each Sandbox; see [08-open-webui.md](08-open-webui.md) |
| `openshell-client-tls` missing | Seal or copy TLS secret into the agent namespace |
| AutoRAG finds no embedding models | OGX needs `inline::sentence-transformers`, not Gemini-as-embedding |

Agent dashboard URL pattern:

```bash
oc get route -A | grep dashboard
```
