#!/usr/bin/env python3
"""
Ingest corpus files into a Milvus vector store via the OGX Files + Vector Stores API.

OGX handles chunking, embedding (using its registered model), and Milvus insertion.
No external embedding API or direct Milvus access needed.

Usage:
  export OGX_SERVICE_URL="http://rfp-ogx-service.rfp-agent.svc.cluster.local:8321"
  python3 ingest-corpus.py
"""

import os
import time
from pathlib import Path

from openai import OpenAI

OGX_URL = os.environ.get("OGX_SERVICE_URL", "http://rfp-ogx-service.rfp-agent.svc.cluster.local:8321")
VECTOR_STORE_NAME = os.environ.get("VECTOR_STORE_NAME", "rfp_knowledge_v1")
EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "sentence-transformers/nomic-ai/nomic-embed-text-v1.5")
CORPUS_DIR = Path(os.environ.get(
    "CORPUS_DIR",
    str(Path(__file__).resolve().parents[2] / "agents" / "rfp-agent" / "corpus"),
))
POLL_SECONDS = int(os.environ.get("OGX_INGEST_POLL_SECONDS", "10"))
POLL_TIMEOUT = int(os.environ.get("OGX_INGEST_POLL_TIMEOUT", "900"))


def ingest():
    client = OpenAI(base_url=f"{OGX_URL}/v1", api_key="unused")

    print(f"OGX: {OGX_URL}")
    print(f"Corpus: {CORPUS_DIR}")
    print(f"Vector store name: {VECTOR_STORE_NAME}")

    md_files = sorted(
        f
        for f in CORPUS_DIR.rglob("*.md")
        if f.name != "README.md" and not f.name.startswith("._")
    )
    print(f"Found {len(md_files)} corpus documents")
    if not md_files:
        raise SystemExit(f"No markdown files under {CORPUS_DIR}")

    existing = client.vector_stores.list()
    for vs in existing.data:
        if vs.name != VECTOR_STORE_NAME:
            continue
        counts = vs.file_counts
        completed = getattr(counts, "completed", 0) or 0
        in_progress = getattr(counts, "in_progress", 0) or 0
        if vs.status == "completed" and completed == len(md_files) and in_progress == 0:
            print(
                f"Store {vs.id} already complete "
                f"({completed}/{len(md_files)} files); skip recreate"
            )
            print(f"VECTOR_STORE_ID={vs.id}")
            return
        print(f"Deleting existing vector store: {vs.id}")
        client.vector_stores.delete(vs.id)

    vector_store = client.vector_stores.create(
        name=VECTOR_STORE_NAME,
        extra_body={
            "provider_id": "milvus",
            "embedding_model": EMBEDDING_MODEL,
        },
    )
    print(f"Created vector store: {vector_store.id}")

    for i, md_file in enumerate(md_files):
        rel = md_file.relative_to(CORPUS_DIR)
        print(f"  [{i+1}/{len(md_files)}] {rel}")

        with open(md_file, "rb") as f:
            file_info = client.files.create(file=(str(rel), f), purpose="assistants")

        client.vector_stores.files.create(
            vector_store_id=vector_store.id,
            file_id=file_info.id,
        )
        time.sleep(0.3)

    deadline = time.time() + POLL_TIMEOUT
    while True:
        vs = client.vector_stores.retrieve(vector_store.id)
        counts = vs.file_counts
        completed = getattr(counts, "completed", 0) or 0
        failed = getattr(counts, "failed", 0) or 0
        total = getattr(counts, "total", 0) or 0
        in_progress = getattr(counts, "in_progress", 0) or 0
        print(
            f"  poll status={vs.status} completed={completed} "
            f"failed={failed} in_progress={in_progress} total={total}"
        )
        if failed:
            raise SystemExit(
                f"OGX vector store {vs.id} has {failed} failed files"
            )
        if vs.status == "completed" and completed == len(md_files) and in_progress == 0:
            break
        if time.time() >= deadline:
            raise SystemExit(
                f"Timed out waiting for vector store {vs.id} "
                f"({completed}/{len(md_files)} files completed)"
            )
        time.sleep(POLL_SECONDS)

    print(f"\nDone! vector_store_id={vector_store.id}")
    print(f"Files ingested: {len(md_files)}")
    print(f"VECTOR_STORE_ID={vector_store.id}")


if __name__ == "__main__":
    ingest()
