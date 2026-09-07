# 05 — Evaluation

## RFP agent (GitOps)

ArgoCD Application `rfp-eval` deploys `agents/rfp-agent/eval/` into `rfp-agent-eval`. The Job `rfp-agent-rag-eval` clones `main`, runs [`platform/scripts/evaluate-rag.py`](../scripts/evaluate-rag.py) against the **pinned AutoRAG winner** (`OGX_VECTOR_STORE_ID` on the Job; vector-io cannot search named `rfp_knowledge_v1` today — [retrieval-truth.md](../../agents/rfp-agent/eval/gold/retrieval-truth.md)), and logs to MLflow experiment **`rfp-agent-rag-evaluation`**.

Benchmark: [`agents/rfp-agent/eval/gold/benchmark_rhoai.json`](../../agents/rfp-agent/eval/gold/benchmark_rhoai.json) (OpenShift AI RFI rows, naming traps, abstain-correctly). Do not treat the agent README 86%/64% figures as a gate until this Job reproduces them.

Re-run: bump `agenthive.io/eval-rev` on the Job and push, or `oc delete job rfp-agent-rag-eval -n rfp-agent-eval` and let Argo recreate it.

EvalHub collections live alongside `platform/gitops/evalhub/`. Job spec: [09-rfp-agent-rhoai.md](09-rfp-agent-rhoai.md).

## RHOAI Copilot (in-repo scenarios)

```bash
python3 agents/rhoai-copilot/eval/run_eval.py
python3 agents/rhoai-copilot/eval/run_eval.py --persona sre --phase monitor
```

There is no Makefile in this monorepo. CI does not yet fail PRs on scenario scores; it does fail on skill-list drift (`check-skill-parity.py`).

## Ops agents

No EvalHub collection yet. Smoke-test: Route up, skill list in startup logs, MCP reachable, cron `latest.md` under `/sandbox/output/`.
