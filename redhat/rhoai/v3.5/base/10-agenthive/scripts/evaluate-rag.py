"""
MLflow RAG Evaluation Script for the RFP Agent.

Evaluates the RAG pipeline using an LLM-as-judge approach:
- Queries OGX /v1/vector-io/query for context retrieval
- Generates answers using Gemini
- Uses Gemini as judge to score faithfulness and relevancy
- Logs all metrics and artifacts to MLflow (kubernetes-namespaced auth)

Results appear in RHOAI Dashboard > Experiments (MLflow).

Required environment variables:
  OPENAI_API_KEY           - Gemini API key
  OGX_BASE_URL             - OGX server URL
  MLFLOW_TRACKING_URI      - MLflow service URL
  MLFLOW_TRACKING_AUTH     - "kubernetes-namespaced"
  MLFLOW_TRACKING_INSECURE_TLS - "true"
  MLFLOW_TRACKING_K8S_NAMESPACE - namespace for workspace header
  MLFLOW_EXPERIMENT        - experiment name (default rfp-agent-rag-evaluation)
  OGX_VECTOR_STORE_ID      - optional explicit store id
  VECTOR_STORE_NAME        - fallback name discovery
  BENCHMARK_PATH           - path to benchmark JSON (question, optional
                             eval_kind, expected_mode, forbidden_names,
                             correct_answer_document_ids)

Optional per-item fields (rfp-agent gold set; ignored if absent):
  eval_kind                  rag | rfi_row | naming | trap
  expected_mode              AUTO | SCAFFOLD | HUMAN
  forbidden_names            product names that must not be recommended
  correct_answer_document_ids
    expected retrieval filenames / document_id values

Deploy as a Kubernetes Job:
  See platform/docs/05-evaluation-mlflow.md.
"""

import json
import logging
import os
import time

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger(__name__)

GEMINI_KEY = os.environ["OPENAI_API_KEY"]
OGX_URL = os.environ.get(
    "OGX_BASE_URL", "http://rfp-ogx-service.rfp-agent.svc.cluster.local:8321"
)
EXPERIMENT = os.environ.get("MLFLOW_EXPERIMENT", "rfp-agent-rag-evaluation")


def discover_vector_store_id() -> str:
    vs_id = os.environ.get("OGX_VECTOR_STORE_ID", "").strip()
    if vs_id:
        return vs_id
    name = os.environ.get("VECTOR_STORE_NAME", "").strip()
    if not name:
        return ""
    import requests

    r = requests.get(
        f"{OGX_URL}/v1/vector_stores",
        headers={"Authorization": "Bearer unused"},
        timeout=15,
    )
    r.raise_for_status()
    for s in r.json().get("data", []):
        if s.get("name") == name:
            log.info(f"Discovered vector store {name} -> {s['id']}")
            return s["id"]
    log.warning(f"No vector store named {name}")
    return ""


def chunk_document_id(chunk: dict) -> str:
    md = chunk.get("metadata") or {}
    return (
        md.get("document_id")
        or md.get("filename")
        or chunk.get("file_id")
        or ""
    )


def looks_like_abstain(answer: str) -> bool:
    a = answer.lower()
    needles = (
        "needs human input",
        "human input required",
        "not in the knowledge",
        "not in knowledge",
        "do not invent",
        "cannot cite",
        "unverifiable",
        "no relevant documents",
        "i don't have",
        "not available in",
    )
    return any(n in a for n in needles)


def naming_violation(answer: str, forbidden: list[str]) -> bool:
    """True when a forbidden name is used as a product, not in a prohibition."""
    if not forbidden:
        return False
    lower = answer.lower()
    for name in forbidden:
        n = name.lower()
        if n not in lower:
            continue
        idx = lower.find(n)
        window = lower[max(0, idx - 32) : idx + len(n) + 32]
        if any(
            p in window
            for p in (
                "never use",
                "do not use",
                "don't use",
                "do not reference",
                "deprecated",
                "not a red hat product",
                "not a separate",
            )
        ):
            continue
        return True
    return False


def expected_doc_hit(retrieved: list[str], expected: list[str]) -> bool:
    if not expected:
        return False
    got = {d.lower() for d in retrieved if d}
    return any(e.lower() in got for e in expected)


def main():
    import requests

    os.environ["MLFLOW_TRACKING_K8S_NAMESPACE"] = (
        open("/var/run/secrets/kubernetes.io/serviceaccount/namespace")
        .read()
        .strip()
    )
    import mlflow

    ns = os.environ["MLFLOW_TRACKING_K8S_NAMESPACE"]
    log.info(
        f"MLflow: {os.environ.get('MLFLOW_TRACKING_URI')}, ns={ns}, "
        f"auth={os.environ.get('MLFLOW_TRACKING_AUTH')}"
    )

    try:
        mlflow.set_experiment(EXPERIMENT)
        log.info("Experiment set OK")
    except Exception as e:
        log.error(f"MLflow failed: {e} - falling back to local")
        mlflow.set_tracking_uri("file:///tmp/mlruns")
        mlflow.set_experiment(EXPERIMENT)

    vs_id = discover_vector_store_id()
    log.info(f"vector_store_id={vs_id or '(unset)'}")

    with open(os.environ.get("BENCHMARK_PATH", "/data/benchmark_data.json")) as f:
        benchmark = json.load(f)
    log.info(f"Loaded {len(benchmark)} questions")

    faith_scores, rel_scores, results = [], [], []

    with mlflow.start_run(run_name="ragas-eval-v1"):
        mlflow.log_param("benchmark_size", len(benchmark))
        mlflow.log_param("judge_model", "gemini-2.5-flash")
        mlflow.log_param("vector_store_id", vs_id or "unset")
        mlflow.log_param(
            "vector_store_name", os.environ.get("VECTOR_STORE_NAME", "")
        )

        for i, item in enumerate(benchmark):
            q = item["question"]
            log.info(f"[{i+1}/{len(benchmark)}] {q[:50]}...")

            ctx = []
            retrieved_ids = []
            try:
                payload = {"query": q, "params": {"max_chunks": 5}}
                if vs_id:
                    payload["vector_store_id"] = vs_id
                r = requests.post(
                    f"{OGX_URL}/v1/vector-io/query",
                    json=payload,
                    timeout=30,
                )
                if r.ok:
                    chunks = r.json().get("chunks", r.json().get("data", []))
                    ctx = [
                        c.get("content", "")
                        for c in chunks
                        if c.get("content")
                    ]
                    retrieved_ids = [
                        chunk_document_id(c) for c in chunks if chunk_document_id(c)
                    ]
            except Exception as e:
                log.warning(f"OGX: {e}")

            expected_mode = item.get("expected_mode", "")
            eval_kind = item.get("eval_kind", "rag")
            forbidden = item.get("forbidden_names") or []
            expected_docs = item.get("correct_answer_document_ids") or []
            if expected_mode in ("HUMAN", "ABSTAIN"):
                gen = (
                    f"Context: {chr(10).join(ctx[:3])[:2000]}\n\nQ: {q}\n"
                    "If the context does not contain a grounded answer, reply "
                    "exactly with NEEDS HUMAN INPUT. Do not invent prices, SLAs, "
                    "or customer names.\nA:"
                )
            else:
                gen = f"Context: {chr(10).join(ctx[:3])[:2000]}\n\nQ: {q}\nA:"

            ans = "No answer"
            try:
                ans_r = requests.post(
                    "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
                    headers={"Authorization": f"Bearer {GEMINI_KEY}"},
                    json={
                        "model": "gemini-2.5-flash",
                        "messages": [
                            {
                                "role": "user",
                                "content": gen,
                            }
                        ],
                        "max_tokens": 512,
                    },
                    timeout=60,
                )
                if ans_r.ok:
                    ans = ans_r.json()["choices"][0]["message"]["content"]
            except Exception as e:
                log.warning(f"Gemini: {e}")

            def judge(prompt):
                try:
                    jr = requests.post(
                        "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
                        headers={"Authorization": f"Bearer {GEMINI_KEY}"},
                        json={
                            "model": "gemini-2.5-flash",
                            "messages": [{"role": "user", "content": prompt}],
                            "max_tokens": 100,
                            "temperature": 0.1,
                        },
                        timeout=30,
                    )
                    return json.loads(
                        jr.json()["choices"][0]["message"]["content"]
                        .replace("```json", "")
                        .replace("```", "")
                        .strip()
                    )["score"]
                except Exception:
                    return 0.5

            fs = judge(
                f"Score faithfulness 0-1. Context: {chr(10).join(ctx[:2])[:1500]}\n"
                f'Answer: {ans[:500]}\nRespond ONLY: {{"score": <float>}}'
            )
            rs = judge(
                f"Score relevancy 0-1. Question: {q}\n"
                f'Answer: {ans[:500]}\nRespond ONLY: {{"score": <float>}}'
            )

            abstain = looks_like_abstain(ans)
            trap_ok = True
            if expected_mode in ("HUMAN", "ABSTAIN") or eval_kind == "trap":
                trap_ok = abstain
            name_fail = naming_violation(ans, forbidden)
            doc_hit = expected_doc_hit(retrieved_ids, expected_docs)

            faith_scores.append(fs)
            rel_scores.append(rs)
            results.append(
                {
                    "id": item.get("id", ""),
                    "q": q[:80],
                    "eval_kind": eval_kind,
                    "expected_mode": expected_mode,
                    "ctx_count": len(ctx),
                    "retrieved_document_ids": retrieved_ids[:5],
                    "has_expected_docs": bool(expected_docs),
                    "expected_document_hit": doc_hit,
                    "abstain": abstain,
                    "trap_ok": trap_ok,
                    "naming_violation": name_fail,
                    "faith": fs,
                    "rel": rs,
                }
            )
            time.sleep(1.5)

        if faith_scores:
            mlflow.log_metric(
                "faithfulness_mean", sum(faith_scores) / len(faith_scores)
            )
            mlflow.log_metric(
                "relevancy_mean", sum(rel_scores) / len(rel_scores)
            )
            mlflow.log_metric("samples_evaluated", len(results))
            mlflow.log_metric(
                "retrieval_success_rate",
                sum(1 for r in results if r["ctx_count"] > 0) / len(results),
            )
            doc_targets = [r for r in results if r.get("has_expected_docs")]
            if doc_targets:
                mlflow.log_metric(
                    "expected_document_hit_rate",
                    sum(1 for r in doc_targets if r.get("expected_document_hit"))
                    / len(doc_targets),
                )
            traps = [r for r in results if r.get("eval_kind") == "trap"]
            if traps:
                mlflow.log_metric(
                    "trap_abstain_rate",
                    sum(1 for r in traps if r.get("trap_ok")) / len(traps),
                )
            naming_items = [r for r in results if r.get("eval_kind") == "naming"]
            if naming_items:
                mlflow.log_metric(
                    "naming_pass_rate",
                    sum(1 for r in naming_items if not r.get("naming_violation"))
                    / len(naming_items),
                )

        with open("/tmp/results.json", "w") as f:
            json.dump(results, f, indent=2)
        mlflow.log_artifact("/tmp/results.json")

        log.info(
            f"DONE: faith={sum(faith_scores)/max(len(faith_scores),1):.3f} "
            f"rel={sum(rel_scores)/max(len(rel_scores),1):.3f}"
        )


if __name__ == "__main__":
    main()
