# Red Hat AI — Data, RAG, and Model Customization

## Overview

Red Hat AI provides a simplified experience for connecting enterprise data to models and agents, moving AI from experimentation to production through enterprise context, customization, and optimization.

## Three Pillars

### 1. Trusted Enterprise Context

- **Data processing:** Prepare and transform enterprise data for AI consumption
- **Synthetic data generation:** Create training data when real data is insufficient or sensitive
- **Feature store:** Manage and serve ML features consistently across training and inference

### 2. Customization and Optimization

| Technique | Description | Use Case |
|-----------|-------------|----------|
| **Prompt Design** | Engineer prompts to enhance model responses | Quick accuracy improvements without training |
| **RAG** | Retrieve relevant information from external sources to augment generation | Ground responses in enterprise knowledge |
| **Fine Tuning** | Customize a base model (OSFT, LoRA, QLoRA) | Domain-specific accuracy requirements |
| **Inference-time Scaling** | Improve response quality through additional reasoning | Better answers without larger models |
| **AutoML** | Automated machine learning pipeline optimization | Available today |
| **AutoRAG** | Automated RAG pipeline optimization | Available today |
| **AutoEval** | Automated evaluation pipeline | Future |

### 3. Evaluation and Governance

**EvalHub** — The quality and governance layer for enterprise AI:
- Unified, framework-agnostic evaluation platform for models, RAG systems, and agents
- Quality, performance, and reliability evaluation
- Risk, safety, and governance assessments
- Security evaluations and red teaming
- Governance-ready evaluation artifacts
- Continuous improvement via MLflow experiment tracking

## AutoRAG — Automated RAG Optimization

AutoRAG automates expert RAG workflows to reduce manual effort and accelerate deployment:

- Automatically tests multiple chunking strategies, embedding models, and retrieval configurations
- Evaluates each configuration against benchmark questions
- Produces an optimized RAG pipeline with the best accuracy/performance trade-off
- Available today in Red Hat OpenShift AI 3.5

### How AutoRAG Works

1. Upload documents to S3-compatible storage
2. Provide evaluation questions with expected answers
3. AutoRAG tests combinations of:
   - Chunking strategies (size, overlap)
   - Embedding models
   - Retrieval parameters (top-k, similarity threshold)
   - Foundation models
4. Produces a leaderboard of RAG patterns ranked by faithfulness
5. Exports winning configuration as indexing + inference notebooks

## AI Safety and Observability

### Runtime Guardrails
- **NeMo Guardrails:** Enforce safety and secure model interactions at runtime
- Content filtering, topic restriction, hallucination detection

### Adversarial Red Teaming
- **Garak:** Proactively catch jailbreaks and vulnerabilities before production
- Automated attack simulation across multiple categories

### Verifiable Supply Chain
- AI BOMs (Bill of Materials) for model integrity
- Model signing for traceability and provenance verification

### Observability
- MLflow for tracing agent steps and monitoring performance metrics
- Role-based access for governing user and AI agent access

## Automation Roadmap

| Capability | Status |
|-----------|--------|
| AutoML | Available today |
| AutoRAG | Available today |
| AutoEval | Future |
| Auto Risk Analysis | Future |
| Auto Red-Teaming | Future |
| Auto Judge Alignment | Future |

## Applicability to RFP Responses

When a customer asks about RAG implementation, model customization, AI evaluation, or connecting enterprise data to models, reference this document for:
- RAG architecture and optimization approach (AutoRAG)
- Fine-tuning options (LoRA, QLoRA, full fine-tune)
- Evaluation framework (EvalHub) capabilities
- AI safety stack (guardrails, red teaming, supply chain)
- Data preparation and synthetic data generation
- Continuous improvement and governance workflows
