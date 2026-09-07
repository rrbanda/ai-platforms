---
name: ogx-rag-builder
description: "Deploy OGX (Open GenAI Stack) servers and build RAG pipelines with vector stores — file upload, chunking, embedding, retrieval, and generation via OpenAI-compatible APIs."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, OGX, RAG, Vector Store, Llama Stack, Retrieval, Embedding, Technology Preview]
---

# Deploy OGX RAG Pipelines

Deploy OGX (Open GenAI Stack) servers and build Retrieval-Augmented Generation pipelines with vector stores on Red Hat OpenShift AI. OGX provides OpenAI-compatible APIs for file management, vector stores, and agentic responses with tool calling.

> **⚠️ TECHNOLOGY PREVIEW:** OGX (Open GenAI Stack) is a Technology Preview feature in Red Hat OpenShift AI. Technology Preview features are not supported with Red Hat production service level agreements (SLAs), might not be functionally complete, and are not recommended for production use. Functionality and APIs may change without notice between releases.

## Trigger Conditions

- "Deploy an OGX server for RAG"
- "Set up a RAG pipeline on OpenShift AI"
- "Create a vector store for my documents"
- "I want to use file_search with my LLM"
- "Configure retrieval-augmented generation"
- "Deploy Llama Stack on RHOAI"
- "Set up OGX with Milvus/Chroma"
- "Build an agentic RAG workflow"
- "Upload documents for RAG retrieval"

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| `mcp_rhoai` | `list_inference_services` | Find available vLLM endpoints for generation and embedding |
| `mcp_rhoai` | `cluster_summary` | Verify RHOAI version supports OGX (≥ 3.4) |
| `mcp_rhoai` | `explore_cluster` | Discover existing OGX deployments and vector stores |
| `mcp_openshift` | `resources_list` | List OGXServer CRs and dependent resources |
| `mcp_openshift` | `pods_list` | Check OGX server pod status |
| `mcp_openshift` | `pods_log` | Debug OGX server startup and runtime errors |
| `mcp_openshift` | `events_list` | Diagnose scheduling and resource issues |

## Procedure

### Phase 1: Prerequisites Assessment

1. Call `mcp_rhoai.cluster_summary` to confirm:
   - RHOAI version ≥ 3.4
   - OGX/Open GenAI Stack component is available
   - KServe is enabled in DataScienceCluster

2. Call `mcp_rhoai.list_inference_services` to identify:
   - A vLLM inference endpoint for generation (chat/completions)
   - An embedding model endpoint (e.g., BGE-M3, nomic-embed)
   - Note: Both endpoints must be accessible from the OGX namespace

3. Verify vector store availability:
   - Call `mcp_openshift.resources_list` for `kind: Deployment` in the target namespace
   - Check for existing PostgreSQL (pgvector), Milvus, or Chroma deployments
   - If none exists, plan vector store deployment (Phase 2)

### Phase 2: Deploy Vector Store (if needed)

4. Deploy the vector store backend. Supported options:

   **Option A: PostgreSQL with pgvector (recommended for simplicity)**
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: pgvector
     namespace: <project-namespace>
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: pgvector
     template:
       metadata:
         labels:
           app: pgvector
       spec:
         containers:
         - name: pgvector
           image: registry.redhat.io/rhel9/postgresql-16:latest
           env:
           - name: POSTGRESQL_USER
             value: ogx
           - name: POSTGRESQL_PASSWORD
             valueFrom:
               secretKeyRef:
                 name: pgvector-credentials
                 key: password
           - name: POSTGRESQL_DATABASE
             value: ogx_vectors
           ports:
           - containerPort: 5432
           volumeMounts:
           - name: data
             mountPath: /var/lib/pgsql/data
         volumes:
         - name: data
           persistentVolumeClaim:
             claimName: pgvector-data
   ```

   **Option B: Milvus (recommended for scale)**
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: milvus-standalone
     namespace: <project-namespace>
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: milvus
     template:
       metadata:
         labels:
           app: milvus
       spec:
         containers:
         - name: milvus
           image: milvusdb/milvus:v2.4-latest
           ports:
           - containerPort: 19530
             name: grpc
           - containerPort: 9091
             name: metrics
   ```

5. Create the corresponding Service and verify pod readiness:
   ```bash
   oc get pods -n <namespace> -l app=<vector-store> -w
   ```

### Phase 3: Deploy OGXServer

6. Create the OGXServer custom resource:
   ```yaml
   apiVersion: ogx.io/v1beta1
   kind: OGXServer
   metadata:
     name: <ogx-server-name>
     namespace: <project-namespace>
   spec:
     inference:
       endpoint: <vllm-inference-url>
       model: <model-name>
     embedding:
       endpoint: <embedding-service-url>
       model: <embedding-model-name>
     vectorStore:
       type: pgvector  # or milvus, chroma
       connection:
         host: <vector-store-service>.<namespace>.svc.cluster.local
         port: 5432
         credentialsSecret: pgvector-credentials
         database: ogx_vectors
     features:
       files: true
       vectorStores: true
       responses: true
       toolCalling: true
   ```

7. Apply the manifest and wait for readiness:
   ```bash
   oc apply -f ogxserver.yaml
   oc wait ogxserver/<name> -n <namespace> --for=condition=Ready --timeout=120s
   ```

8. Call `mcp_openshift.pods_list` to verify the OGX server pod is Running.

### Phase 4: Build RAG Pipeline

9. Obtain the OGX server endpoint:
   ```bash
   OGX_URL=$(oc get ogxserver <name> -n <namespace> -o jsonpath='{.status.endpoint}')
   ```

10. Upload files for RAG ingestion (OpenAI Files API):
    ```bash
    curl -X POST "${OGX_URL}/v1/files" \
      -H "Authorization: Bearer ${API_KEY}" \
      -F "file=@/path/to/document.pdf" \
      -F "purpose=assistants"
    ```

11. Create a vector store and attach files:
    ```bash
    curl -X POST "${OGX_URL}/v1/vector_stores" \
      -H "Authorization: Bearer ${API_KEY}" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "my-knowledge-base",
        "file_ids": ["<file-id-1>", "<file-id-2>"],
        "chunking_strategy": {
          "type": "auto"
        }
      }'
    ```

12. Wait for vector store processing to complete:
    ```bash
    curl -s "${OGX_URL}/v1/vector_stores/<vs-id>" \
      -H "Authorization: Bearer ${API_KEY}" | jq '.status, .file_counts'
    ```
    Expected: `status: "completed"`, all files in `file_counts.completed`.

### Phase 5: Query with RAG (Responses API)

13. Send a query using the Responses API with `file_search` tool:
    ```bash
    curl -X POST "${OGX_URL}/v1/responses" \
      -H "Authorization: Bearer ${API_KEY}" \
      -H "Content-Type: application/json" \
      -d '{
        "model": "<model-name>",
        "input": "What does the document say about deployment architecture?",
        "tools": [
          {
            "type": "file_search",
            "vector_store_ids": ["<vs-id>"]
          }
        ]
      }'
    ```

14. For multi-turn agentic conversations:
    ```bash
    curl -X POST "${OGX_URL}/v1/responses" \
      -H "Authorization: Bearer ${API_KEY}" \
      -H "Content-Type: application/json" \
      -d '{
        "model": "<model-name>",
        "input": "Follow-up question based on previous context",
        "previous_response_id": "<response-id>",
        "tools": [
          {"type": "file_search", "vector_store_ids": ["<vs-id>"]}
        ]
      }'
    ```

### Phase 6: Verification

15. Verify end-to-end pipeline health:
    - Call `mcp_openshift.pods_list` — OGX server pod is Running
    - Call `mcp_openshift.pods_log` for the OGX pod — no error patterns
    - Test a simple query and confirm retrieval results include source citations
    - Check vector store file counts match uploaded documents

## Output Format

```
# OGX RAG Pipeline Deployment Report

## OGX Server
- Name: {ogx-server-name}
- Namespace: {namespace}
- Status: {Ready/NotReady}
- Endpoint: {ogx-url}

## Infrastructure
- Inference Model: {model-name} @ {inference-url}
- Embedding Model: {embedding-model} @ {embedding-url}
- Vector Store: {type} @ {host}:{port}

## RAG Pipeline
- Files Uploaded: {count}
- Vector Store: {vs-name} (status: {status})
- Chunking Strategy: {auto/static}
- File Processing: {completed}/{total}

## API Endpoints Available
- Files API: {ogx-url}/v1/files
- Vector Stores API: {ogx-url}/v1/vector_stores
- Responses API: {ogx-url}/v1/responses

## Test Query Result
- Query: "{sample-query}"
- Retrieved {n} chunks from vector store
- Response includes source citations: {yes/no}

## Next Steps
- {Upload additional documents}
- {Tune chunking strategy for domain-specific content}
- {Configure guardrails for production use}
```

## Safety Constraints

- Never expose vector store credentials in logs or output — always reference Kubernetes Secrets
- Verify inference endpoint authentication before configuring OGX — do not pass credentials in plain text
- Do not upload sensitive documents (PII, credentials, internal secrets) without user confirmation
- Respect namespace isolation — OGX server should only access vector stores within its own namespace or explicitly shared ones
- Warn user that OGX is Technology Preview and not suitable for production workloads with SLA requirements
- Do not modify existing inference service configurations without explicit user consent
- All file uploads should go through the OGX Files API, never directly to the vector store

## Disconnected Environment Notes

- **Container images**: OGX server images must be mirrored to the internal registry. Add OGX-related images to the `ImageSetConfiguration`:
  ```yaml
  mirror:
    additionalImages:
      - name: registry.redhat.io/rhoai/ogx-server-rhel9:latest
  ```
- **Vector store images**: Mirror the chosen vector store image (PostgreSQL from `registry.redhat.io`, or Milvus from a pre-staged mirror)
- **Embedding models**: Ensure the embedding model is deployed locally via a mirrored vLLM serving runtime — external embedding APIs are not reachable
- **Document ingestion**: Files must be available locally; no external URL fetching is possible in disconnected environments
- **OGX CRD**: The OGX operator CRD (`ogx.io/v1beta1`) is bundled with RHOAI ≥ 3.4 — no additional operator mirroring needed
