#!/usr/bin/env python3
"""
Convert benchmark_data.json to RAGAS evaluation JSONL format.

Uses the OGX /v1/vector-io/query API for retrieval (consistent with the
rh-knowledge-retrieval skill) and Gemini for answer generation.

Output format: one JSON object per line with the four RAGAS native columns:
  user_input, response, retrieved_contexts, reference

Requirements: requests
Run from within the cluster (Job, workbench, or agent pod).
"""

import json
import os
import sys
import time
import requests
from pathlib import Path

GEMINI_API_KEY = os.environ.get(
    "OPENAI_API_KEY", os.environ.get("GEMINI_API_KEY", "")
)
GEMINI_CHAT_URL = (
    "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
)
GEMINI_MODEL = os.environ.get("LLM_MODEL", "gemini-2.5-flash")

OGX_BASE_URL = os.environ.get(
    "OGX_BASE_URL",
    "http://autorag-llamastack-service.autorag.svc.cluster.local:8321",
)
VECTOR_STORE_ID = os.environ.get(
    "OGX_VECTOR_STORE_ID", "vs_855c862e-c353-422e-bd9e-f28adea563c0"
)
TOP_K = int(os.environ.get("RAG_TOP_K", "5"))

BENCHMARK_PATH = Path(
    os.environ.get(
        "BENCHMARK_PATH",
        str(Path(__file__).parent.parent / "corpus" / "test-data" / "benchmark_data.json"),
    )
)
OUTPUT_PATH = Path(
    os.environ.get(
        "EVAL_DATASET_PATH",
        str(Path(__file__).parent.parent / "corpus" / "test-data" / "ragas-eval-dataset.jsonl"),
    )
)


def query_ogx(query: str, top_k: int = TOP_K) -> list[str]:
    """Retrieve contexts via the OGX /v1/vector-io/query API."""
    resp = requests.post(
        f"{OGX_BASE_URL}/v1/vector-io/query",
        json={
            "vector_store_id": VECTOR_STORE_ID,
            "query": query,
            "params": {"max_chunks": top_k},
        },
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()
    chunks = data.get("chunks", [])
    return [c.get("content", "") for c in chunks if c.get("content")]


def get_agent_answer(question: str, contexts: list[str]) -> str:
    """Generate the agent's answer using Gemini with retrieved contexts."""
    context_text = "\n\n---\n\n".join(contexts) if contexts else "No context available."

    messages = [
        {
            "role": "system",
            "content": (
                "You are a Red Hat RFP response agent. Answer the question using ONLY "
                "the provided context. Be specific and cite product names accurately."
            ),
        },
        {
            "role": "user",
            "content": f"Context:\n{context_text}\n\nQuestion: {question}",
        },
    ]

    for attempt in range(3):
        resp = requests.post(
            GEMINI_CHAT_URL,
            headers={
                "Authorization": f"Bearer {GEMINI_API_KEY}",
                "Content-Type": "application/json",
            },
            json={
                "model": GEMINI_MODEL,
                "messages": messages,
                "max_tokens": 1024,
                "temperature": 0.1,
            },
            timeout=90,
        )
        if resp.status_code == 429:
            wait = 30 * (attempt + 1)
            print(f"  Rate limited, waiting {wait}s...")
            time.sleep(wait)
            continue
        resp.raise_for_status()
        data = resp.json()
        choices = data.get("choices", [])
        if choices:
            msg = choices[0].get("message", {})
            content = msg.get("content")
            if content:
                return content
        raise KeyError(f"No content in response: {json.dumps(data)[:200]}")

    raise RuntimeError("Exhausted retries on Gemini chat API")


def main():
    if not GEMINI_API_KEY:
        print("ERROR: Set OPENAI_API_KEY or GEMINI_API_KEY environment variable")
        sys.exit(1)

    print(f"Loading benchmark data from {BENCHMARK_PATH}")
    benchmark = json.loads(BENCHMARK_PATH.read_text())
    print(f"  Found {len(benchmark)} questions")
    print(f"  OGX endpoint: {OGX_BASE_URL}")
    print(f"  Vector store: {VECTOR_STORE_ID}")
    print(f"  Output: {OUTPUT_PATH}")

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    with open(OUTPUT_PATH, "w") as fout:
        for i, item in enumerate(benchmark, 1):
            question = item["question"]
            reference = item["correct_answers"][0]

            print(f"\n[{i}/{len(benchmark)}] {question[:80]}...")

            print("  Querying OGX...")
            try:
                contexts = query_ogx(question)
            except Exception as e:
                print(f"  ERROR querying OGX: {e}")
                contexts = []

            if not contexts:
                print("  WARNING: No contexts returned")
                contexts = ["No relevant context found in knowledge base."]
            else:
                print(f"  Retrieved {len(contexts)} contexts")

            print("  Generating answer...")
            try:
                response = get_agent_answer(question, contexts)
            except Exception as e:
                print(f"  ERROR generating answer: {e}")
                response = "Error: could not generate answer"

            record = {
                "user_input": question,
                "response": response,
                "retrieved_contexts": contexts,
                "reference": reference,
            }
            fout.write(json.dumps(record) + "\n")
            fout.flush()

            time.sleep(2)

    print(f"\n{'=' * 60}")
    print(f"RAGAS JSONL dataset saved to {OUTPUT_PATH}")
    print(f"Total samples: {len(benchmark)}")


if __name__ == "__main__":
    main()
