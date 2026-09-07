# 08 — RHOAI 3.5 Documentation Reference

> Key RHOAI 3.5 feature areas mapped for skill development.
> Source: https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/
> Last updated: 2026-08-22

---

## Documentation Index

The RHOAI 3.5 docs cover 31 feature areas across 9 lifecycle phases. This file captures the essential technical details needed to write skills for the 19 uncovered areas.

---

## llm-d Distributed Inference (GA)

**CRD:** `LLMInferenceService` (serving.kserve.io/v1alpha1)
**Components:** Model server pods + Endpoint Picker (EPP) + Gateway HTTPRoute
**Prerequisites:** GatewayClass + Gateway `openshift-ai-inference` in `openshift-ingress`, OCP 4.19.9+, optional LeaderWorkerSet for multi-node

**Minimal CR:**
```yaml
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: <service-name>
spec:
  replicas: 2
  model:
    uri: hf://<org>/<model-name>
    name: <org>/<model-name>
  router:
    route: {}
    gateway: {}
    scheduler: {}
  template:
    containers:
    - name: main
      resources:
        limits:
          nvidia.com/gpu: "1"
```

**Model URI formats:** `hf://` (HuggingFace), `pvc://` (PVC), `oci://` (OCI image), `s3://`
**Scheduler plugins:** `prefix-cache-scorer` (KV-cache affinity), `queue-scorer` (load balancing)
**Parallelism:** `spec.parallelism.tensor`, `spec.parallelism.data`, `spec.parallelism.dataLocal`
**Multi-node:** Requires LeaderWorkerSet Operator when parallelism > 8 accelerators

---

## NeMo Guardrails (GA in 3.5)

**CRD:** `NemoGuardrails` (trustyai.opendatahub.io/v1alpha1)
**Operator:** TrustyAI (DSC component `trustyai` must be `Managed`)
**Endpoints:** `/v1/guardrails/checks` (validation only), `/v1/chat/completions` (full LLM with rails)

**Built-in detectors (no external service needed):**
- Sensitive data detection (PII, secrets, API keys)
- Content filtering
- Regex pattern matching
- Custom validation rules

**ConfigMap-based configuration:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nemo-config
data:
  config.yml: |
    models:
    - type: main
      engine: openai
      model: <model-name>
    rails:
      input:
        flows:
        - self check input
      output:
        flows:
        - self check output
```

**MCP Gateway integration:** `spec.template.pod.mcpGateway` for guardrail enforcement on agent tool calls
**OTel support:** Built-in OpenTelemetry for monitoring guardrail performance

---

## Model Catalog (GA)

**Dashboard path:** AI Hub > Models > Catalog
**Features:** Search by name/description/provider, filter by task/license, performance benchmarks per hardware config
**Key metrics:** Cold-start load time, minimum vRAM, validated tool-calling configurations
**Actions:** Deploy model, register to model registry, compare benchmarks
**Validated args:** Models with tool-calling show validated `vllm serve` CLI arguments
**Catalog sources:** Default Red Hat catalog + admin-managed custom sources (ModelCatalogSource CR)

---

## Model Registry (GA)

**DSC component:** `modelregistry` (enabled by default in 3.5)
**Database:** External MySQL or PostgreSQL required for production
**Dashboard path:** AI Hub > Model Registry
**API:** `/api/model_registry/v1alpha3/` endpoints
**RBAC:** Admin creates registries and grants group access
**Operations:** Register model, create version, add artifacts, deploy from registry, archive versions
**Labels:** Support for standard labels (AB testing, environment tagging)

---

## Distributed Training (GA)

**Operators:** KubeRay (Ray), Kubeflow Training Operator (PyTorch), Kueue (scheduling)
**DSC components:** `ray`, `trainingoperator`, `kueue`

**RayJob with Kueue:**
```yaml
apiVersion: ray.io/v1
kind: RayJob
metadata:
  labels:
    kueue.x-k8s.io/queue-name: <local-queue>
spec:
  shutdownAfterJobFinishes: true
  entrypoint: python /home/ray/train.py
  runtimeEnvYAML: |
    pip: [torch, transformers]
  rayClusterSpec:
    headGroupSpec: ...
    workerGroupSpecs: ...
```

**PyTorchJob:** Kubeflow Training Operator CRD for distributed PyTorch training
**CodeFlare SDK:** Python SDK for creating RayCluster/RayJob without Kubernetes YAML
**RDMA:** Optional GPU Direct RDMA for multi-node GPU interconnect
**Accelerators:** NVIDIA and AMD GPUs supported

---

## Kueue Quota Management (GA)

**Components:** ClusterQueue, LocalQueue, ResourceFlavor, Workload
**Managed workloads:** RayJob, RayCluster, PyTorchJob, Notebook (workbenches), InferenceService
**Namespace label:** `kueue.openshift.io/managed=true` (auto-applied by dashboard for new projects)
**Workload label:** `kueue.x-k8s.io/queue-name=<local-queue>` on workload YAML
**Operator:** Red Hat build of Kueue Operator (replaces embedded kueue in 3.5)
**Migration:** Must migrate from embedded kueue before upgrading to 3.5

---

## LM-Eval / EvalHub (GA)

**CRD:** `LMEvalJob` (trustyai.opendatahub.io)
**Operator:** TrustyAI
**EvalHub providers:** `lm_evaluation_harness` (167 benchmarks), `garak` (12 benchmarks), `guidellm` (4 benchmarks)
**Collections:** Group benchmarks into reusable evaluation suites
**Benchmarks:** MMLU, HellaSwag, GSM8K, ARC Challenge, WinoGrande, TruthfulQA, etc.
**Dashboard:** Technology Preview UI for configuring and viewing evaluations
**Pass criteria:** Configurable thresholds per benchmark (pass/fail/partially_failed)

---

## Model Monitoring — TrustyAI (GA)

**Metrics:** SPD (Statistical Parity Difference), DIR (Disparate Impact Ratio)
**Data drift:** Monitor input data distribution changes for deployed models
**Integration:** Prometheus metrics + OpenShift monitoring stack
**Visualization:** Dashboard metrics and threshold configuration

---

## Hardware Profiles (GA)

**Features:** Accelerator profiles (GPU types), CPU-only profiles, node selectors
**Usage:** Workbenches, model serving, AI pipelines
**Admin config:** Settings menu in dashboard
**Node targeting:** Select specific worker nodes by accelerator type

---

## MaaS Subscriptions & Governance (GA)

**Resources:** MaaSSubscription, MaaSAuthPolicy, MaaSModelRef (all `maas.opendatahub.io/v1alpha1`)
**Subscriptions:** Token limits, rate limiting, group-based access, priority levels
**API keys:** Self-service create/list/revoke, admin provisioning, custom expiration
**Usage tracking:** Observability dashboard (TP), CSV export for cost attribution
**Multi-runtime:** llm-d (GA) and vLLM (TP) through same governance
**External models (TP):** Route to AWS Bedrock, Azure OpenAI, Google Vertex AI
**External OIDC (TP):** Enterprise-wide access without OpenShift user accounts

---

## Feature Store — Feast (GA)

**CRD:** `FeatureStore`
**Components:** Online store (Redis), offline store (BigQuery/Snowflake/files), registry (PostgreSQL/SQLite)
**Materialization:** CronJob moves data from offline to online store
**Prometheus metrics:** Feature server performance, online store ops, freshness
**CLI:** `feast plan`, `feast apply`, `feast materialize-incremental`, `feast get-online-features`

---

## OGX / RAG (Technology Preview)

**CRD:** `OGXServer` (ogx.io/v1beta1)
**Renamed from:** Llama Stack (all configs/envvars updated to OGX)
**Dependencies:** PostgreSQL, vLLM inference endpoint, vector store (Milvus, Chroma)
**APIs:** OpenAI-compatible (Files, VectorStores, Responses with file_search tool)
**RAG workflow:** File upload > chunking > embedding > vector store > retrieval > generation
**Agentic:** Supports tool calling and multi-turn conversations via Responses API

---

## Garak Security Scanning (Technology Preview)

**Provider:** EvalHub Garak provider (inline or remote via Kubeflow Pipelines)
**Probes:** SPOIntent, SPOIntentUserAugmented, TranslationIntent, TAPIntent
**Detectors:** MulticlassJudge with configurable judge model
**Config:** Garak scan configuration YAML with probe_spec, detector settings
**Thresholds:** `eval_threshold` (default 0.5), `max_dan_samples`, `generations`

---

## AutoML (Technology Preview)

**Features:** Dashboard UI for optimization runs, model leaderboard, notebook generation
**Workflow:** Configure > train > compare > register best model

---

## AutoRAG (Technology Preview)

**Features:** Dashboard UI for RAG pattern optimization, leaderboard, notebook generation
**Workflow:** Configure > evaluate RAG patterns > select best > generate notebook

---

## GenAI Playground (Technology Preview)

**Features:** Interactive model experimentation, parameter tuning, guardrails testing
**Integration:** NeMo Guardrails applied in playground context
