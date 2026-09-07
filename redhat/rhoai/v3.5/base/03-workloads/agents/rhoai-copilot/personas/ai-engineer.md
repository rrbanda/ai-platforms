# AI Engineer Persona

## Role

Builds production-ready AI and agentic applications on RHOAI. Works with the model catalog to discover, evaluate, and deploy gen AI models. Uses OGX to build RAG pipelines and agentic workflows. Focuses on model customization, serving at scale, and integrating models into applications via APIs.

This is a distinct role from Data Scientist (who focuses on experimentation) — the AI engineer focuses on **application-level integration**, production model deployment, and building compound AI systems.

## Primary Lifecycle Phases

- **Deploy** — Model serving via MaaS, llm-d, KServe; gateway configuration; API key management
- **Develop** — RAG applications with OGX, agentic workflows, GenAI playground, model customization
- **Evaluate** — Model benchmarking, LM-Eval jobs, comparing performance across hardware configurations
- **Plan** — Model selection from catalog, VRAM estimation, serving runtime selection
- **Maintain Safety** — Guardrails configuration, Garak security scanning, content filtering

## Key Skills

| Skill | Phase | Usage |
|-------|-------|-------|
| `maas-enable` | Deploy | Bootstrap Models-as-a-Service on the cluster |
| `maas-deploy-model` | Deploy | Deploy models to MaaS with governance and API keys |
| `rhoai-model-lifecycle` | Deploy | Manage model serving and versions |
| `model-promotion-workflow` | Deploy | Promote models between environments |
| `serving-runtime-advisor` | Plan | Choose optimal runtime (vLLM, llm-d, KServe) for a model |
| `capacity-forecaster` | Plan | Estimate GPU/memory requirements for model serving |
| `experiment-tracker` | Develop | Track fine-tuning experiments in MLflow |
| `training-planner` | Plan | Plan model customization/fine-tuning resources |
| `maas-debug` | Monitor | Troubleshoot MaaS gateway and model serving issues |

## Example Interactions

- "Deploy Llama-3.1-8B-Instruct to MaaS with API key access for my team"
- "How much VRAM do I need to serve Qwen3-72B with tensor parallelism?"
- "Enable MaaS on this cluster so I can expose models via the gateway"
- "Which serving runtime should I use for a RAG application — vLLM or llm-d?"
- "Set up OGX with a vector store for my document retrieval pipeline"
- "Compare inference performance of granite-3b vs granite-8b on A10G GPUs"
- "Configure guardrails to filter PII from model responses"

## Key RHOAI 3.5 Features

- **Model Catalog** — Curated library of validated gen AI models with performance benchmarks
- **Models-as-a-Service (MaaS)** — Governed LLM access via AI Gateway with API key auth
- **OGX (Open GenAI Stack)** — Build RAG and agentic applications with OpenAI-compatible APIs
- **llm-d** — Distributed inference with prefill-decode split for large models
- **GenAI Playground** — Interactive model experimentation
- **AutoRAG** — Automated RAG pipeline configuration and optimization
- **LM-Eval** — Standardized model evaluation and benchmarking
- **Garak** — Security scanning for LLM vulnerabilities

## MCP Servers Used

- RHOAI MCP (primary — model serving, model registry)
- MLflow MCP (experiment tracking for fine-tuning)
- ArgoCD MCP (deployment status of model serving infrastructure)
- GitHub MCP (for PR-based model deployment configurations)
