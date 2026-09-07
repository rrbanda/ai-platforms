"""
Production indexing script for the RFP Agent RAG pipeline.

Replicates the logic from AutoRAG's indexing.ipynb output (Pattern2 winner).
Reads extracted text from the AutoRAG pipeline's S3 artifacts, chunks it
using the optimized settings, embeds via OGX, and inserts into Milvus.

Run this as a Kubernetes Job after AutoRAG completes:
  oc apply -f platform/infra/runtime/indexing-job.yaml

Configuration (from AutoRAG Pattern2, faithfulness=0.617):
  - Chunking: recursive, size=2048, overlap=128
  - Embedding: sentence-transformers/nomic-ai/nomic-embed-text-v1.5 (768 dim)
  - Vector store: Milvus via OGX remote::milvus provider

Required environment variables:
  OGX_CLIENT_BASE_URL  - OGX server URL (e.g. http://rfp-ogx-service.rfp-agent.svc.cluster.local:8321)
  OGX_CLIENT_API_KEY   - OGX API key (can be "unused" if no auth)
  AWS_S3_ENDPOINT      - MinIO endpoint (e.g. http://minio.minio.svc.cluster.local:9000)
  AWS_ACCESS_KEY_ID    - MinIO access key
  AWS_SECRET_ACCESS_KEY - MinIO secret key
  AWS_S3_BUCKET        - Bucket name (default: rfp-agent-knowledge)
  VECTOR_STORE_ID      - Milvus collection ID from AutoRAG output
  PIPELINE_RUN_ID      - AutoRAG pipeline run ID (for locating artifacts in S3)
  TEXT_EXTRACTION_ID   - Text extraction task ID (for locating extracted text in S3)
"""

import json
import logging
import os
import sys
from pathlib import Path

import boto3
from botocore.client import Config as BotoConfig

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger(__name__)

OGX_URL = os.environ["OGX_CLIENT_BASE_URL"]
OGX_KEY = os.environ.get("OGX_CLIENT_API_KEY", "unused")
S3_ENDPOINT = os.environ["AWS_S3_ENDPOINT"]
S3_KEY = os.environ["AWS_ACCESS_KEY_ID"]
S3_SECRET = os.environ["AWS_SECRET_ACCESS_KEY"]
S3_BUCKET = os.environ.get("AWS_S3_BUCKET", "rfp-agent-knowledge")
COLLECTION = os.environ["VECTOR_STORE_ID"]
PIPELINE_RUN_ID = os.environ["PIPELINE_RUN_ID"]
TEXT_EXTRACTION_ID = os.environ["TEXT_EXTRACTION_ID"]

EMBEDDING_MODEL = "sentence-transformers/nomic-ai/nomic-embed-text-v1.5"
CHUNK_SIZE = 2048
CHUNK_OVERLAP = 128


def main():
    import httpx
    from ai4rag.rag.chunking import LangChainChunker
    from ai4rag.rag.embedding.ogx import OGXEmbeddingModel, OGXEmbeddingParams
    from ai4rag.rag.vector_store.ogx import OGXVectorStore
    from langchain_core.documents import Document
    from ogx_client import OgxClient

    s3 = boto3.client(
        "s3",
        endpoint_url=S3_ENDPOINT,
        aws_access_key_id=S3_KEY,
        aws_secret_access_key=S3_SECRET,
        config=BotoConfig(signature_version="s3v4"),
        region_name="us-east-1",
        verify=False,
    )

    try:
        client = OgxClient(base_url=OGX_URL, api_key=OGX_KEY)
        client.models.list()
        log.info(f"Connected to OGX: {OGX_URL}")
    except Exception:
        client = OgxClient(
            base_url=OGX_URL,
            api_key=OGX_KEY,
            http_client=httpx.Client(verify=False),
        )
        log.info(f"Connected to OGX (insecure TLS): {OGX_URL}")

    chunker = LangChainChunker(
        method="recursive",
        chunk_size=CHUNK_SIZE,
        chunk_overlap=CHUNK_OVERLAP,
    )

    params = OGXEmbeddingParams(embedding_dimension=768)
    embedding_model = OGXEmbeddingModel(
        client=client,
        model_id=EMBEDDING_MODEL,
        params=params,
    )

    ogx_vector_store = OGXVectorStore(
        embedding_model=embedding_model,
        client=client,
        provider_id="milvus",
        distance_metric="cosine",
        reuse_collection_name=COLLECTION,
    )
    log.info(f"Vector store: {COLLECTION}")

    prefix = (
        f"documents-rag-optimization-pipeline/{PIPELINE_RUN_ID}/"
        f"text-extraction/{TEXT_EXTRACTION_ID}/extracted_text/"
    )
    resp = s3.list_objects_v2(Bucket=S3_BUCKET, Prefix=prefix)
    objects = [o for o in resp.get("Contents", []) if o["Key"].endswith(".md")]
    log.info(f"Found {len(objects)} extracted text files in S3")

    if not objects:
        log.error(f"No .md files found at s3://{S3_BUCKET}/{prefix}")
        log.error("Check PIPELINE_RUN_ID and TEXT_EXTRACTION_ID env vars")
        sys.exit(1)

    total_chunks = 0
    for obj in objects:
        content = (
            s3.get_object(Bucket=S3_BUCKET, Key=obj["Key"])["Body"]
            .read()
            .decode("utf-8", errors="replace")
        )
        filename = obj["Key"].split("/")[-1]
        doc_id = filename.replace(".md.md", "").replace(".md", "")

        document = Document(
            page_content=content,
            metadata={"document_id": doc_id},
        )

        chunks = chunker.split_documents([document])
        ogx_vector_store.add_documents(chunks)
        total_chunks += len(chunks)
        log.info(f"  {doc_id}: {len(chunks)} chunks")

    log.info(f"DONE: {total_chunks} total chunks indexed into {COLLECTION}")


if __name__ == "__main__":
    main()
