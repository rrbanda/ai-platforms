# 08 — Open WebUI in front of Hermes agents

One Open WebUI instance can drive **more than one** Hermes agent. Each agent is an OpenAI-compatible backend (`:8642/v1`). The model picker is how you choose the agent. Tools and RAG still run **on that agent’s Sandbox**, not in Open WebUI.

Hermes documents this as “multiple connections” (their laptop **profiles**). On AgentHive each Sandbox is already one agent, so you do not create `hermes profile`s.

## What this PoC deploys

| Piece | Where |
|-------|--------|
| Open WebUI | Argo Application `open-webui`, namespace `open-webui`, image `ghcr.io/open-webui/open-webui:v0.11.0` |
| Backends (v1) | rfp-agent ClusterIP port `8642` |
| Model ids | `API_SERVER_MODEL_NAME` on the Sandbox (`rfp-agent`) |
| Keys | SealedSecret `open-webui-providers` (`WEBUI_SECRET_KEY`, `OPENAI_API_KEYS`) |

Public **Routes stay on the Hermes dashboard** (`9119`). Do **not** expose `:8642` on a Route.

```text
User → Open WebUI Route
        └─ Bearer rfp-agent api-server-key → rfp-agent-dashboard.rfp-agent:8642
```

## Open the UI

```bash
echo "https://$(oc get route open-webui -n open-webui -o jsonpath='{.spec.host}')"
```

The first visitor creates the Open WebUI **admin** account. That is separate from Hermes dashboard basic auth (`admin` + `dashboard-password` on each `*-auth` secret). Any Open WebUI user who can pick a model can talk to that agent (its soul, skills, and RAG).

`ENABLE_PERSISTENT_CONFIG=false` so GitOps env (`OPENAI_API_BASE_URLS` / keys) wins over the Open WebUI database.

On ROSA, `gp3-csi` uses WaitForFirstConsumer. If Argo applies the PVC before the Deployment, it waits forever for the volume to become Healthy. The Deployment and PVC must land in the same apply (no later sync-wave on the Deployment). If a first sync sticks on `waiting for healthy state of PersistentVolumeClaim/open-webui-data`, apply `oc apply -k platform/gitops/open-webui` once so the pod can bind the volume.

## Isolation rules

- Pick **rfp-agent** for the RFP corpus.
- Do not turn on Open WebUI’s own document RAG against account files; that bypasses agent soul and skills.
- File attach in Open WebUI does **not** land in the agent `/sandbox`. rfp-agent must use extracted text already in the chat. Durable knowledge still goes in `agents/*/corpus/` + ingest.
- rfp-agent **retrieval** uses the pinned AutoRAG winner (`OGX_VECTOR_STORE_ID` / vector-io). Ingest still writes named `rfp_knowledge_v1`; that named store is not what `/v1/vector-io/query` searches today. See [retrieval-truth.md](../../agents/rfp-agent/eval/gold/retrieval-truth.md) and [09-rfp-agent-rhoai.md](09-rfp-agent-rhoai.md).

## Add another agent later

1. Set `API_SERVER_MODEL_NAME` (and `API_SERVER_PORT=8642`) on that agent’s `sandbox.yaml`.
2. Append `http://<svc>.<ns>.svc.cluster.local:8642/v1` to `OPENAI_API_BASE_URLS` in [`platform/gitops/open-webui/deployment.yaml`](../gitops/open-webui/deployment.yaml) (same order as keys).
3. Reseal `open-webui-providers` `OPENAI_API_KEYS` as `key1;key2;key3` matching that order (`platform/gitops/secrets/seal-secrets.sh`).
4. Commit, push, wait for Argo. Do not `oc patch` Sandbox `operatingMode`.

## SCC

Open WebUI uses ServiceAccount `open-webui` bound to `anyuid` only. Do not bind privileged SCC to this UI.

## If models do not appear

- URL must include `/v1`.
- `GET /v1/models` on the agent with that agent’s `api-server-key` must return a unique `id` (not two `hermes-agent`s).
- Gateway log: `/tmp/hermes-gateway.log` in the sandbox pod.
- Connection test in Open WebUI is not a model-list check.
