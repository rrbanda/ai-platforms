# Red Hat AI Platform — Inference Capabilities

## Overview

Red Hat AI delivers consistent, fast, and cost-effective inference across the hybrid cloud. The inference stack comprises three layers: a model catalog, a high-performance runtime (vLLM), and a distributed inference orchestrator (llm-d).

## Core Components

### vLLM — Inference Runtime

vLLM is Red Hat AI's optimized inference engine. It connects model creators to accelerated hardware providers and delivers fast, cost-effective, consistent inference for large language models.

Key facts:
- Open-source inference engine purpose-built for LLMs
- Supports all major model families: Llama, Qwen, DeepSeek, Gemma, Mistral, Molmo, Phi, Nemotron, Granite
- Runs on NVIDIA GPUs, AMD Instinct MI350X/MI355X, Intel Xeon, Google TPUs, AWS Inferentia/Neuron, IBM Spyre
- Available natively in Red Hat OpenShift AI and as the enterprise vLLM in RHEL AI
- Improved performance and cost benefits compared to other inference runtimes at scale

### llm-d — Distributed Inference at Scale

llm-d reimagines how LLMs run on Kubernetes. It provides distributed, scalable generative AI inference for enterprise production.

Key benefits:
- Lower infrastructure cost and increased efficiency
- Faster response times for multi-turn and agent workloads
- Simplified management for platform administrators
- Cost-effective, predictable performance at scale
- Builds on vLLM's core innovations with improved performance as volume increases

### AI Gateway

Enterprise GenAI Inference Platform providing:
- API Management for any model
- Token tracking and chargeback
- Authentication and access control
- Rate limiting and quotas
- Centralized governance for Model-as-a-Service

### Model Catalog (Red Hat AI on Hugging Face)

Collection of third-party models with two tiers:

**Validated Models:**
- Tested using realistic scenarios
- Assessed for performance across a range of hardware
- Benchmarked using GuideLLM and LM Eval Harness

**Optimized Models:**
- Compressed for speed and efficiency using LLM Compressor
- Designed to run faster, use fewer resources, maintain accuracy
- Uses latest compression algorithms (quantization, pruning, distillation)

Supported model families: Llama, Qwen, Mistral/Voxtral, DeepSeek, Molmo, Granite, Nemotron, Gemma, Phi, K2

### Model Optimization Tooling

| Tool | Purpose |
|------|---------|
| LLM Compressor | Reduce model size and compute requirements while preserving accuracy |
| GuideLLM | Evaluate LLM inference performance for capacity planning |
| LM Eval Harness | Evaluate accuracy across tasks and benchmarks |

## Hardware Accelerator Support

| Accelerator | Vendor | Status |
|-------------|--------|--------|
| GPU (including Blackwell, Vera Rubin) | NVIDIA | Day 0 RHEL support |
| Instinct MI350X / MI355X | AMD | Supported |
| Xeon | Intel | Supported |
| TPU | Google | Supported |
| Neuron / Inferentia | AWS | Supported |
| Spyre / AIU | IBM | Supported |

## Model-as-a-Service (MaaS)

Red Hat AI enables IT to serve common models centrally:
- Curated, open models available through console
- Centralized pool of hardware including GPUs
- Dedicated UI for Platform Engineering for AI
- Developers consume models via APIs
- Shared resources business model with access policies, chargeback, and quotas

## Deployment Environments

Red Hat AI inference runs across:
- Edge
- Physical (bare metal)
- Virtual
- Private Cloud
- Public Cloud (AWS, Azure, GCP)
- Sovereign Cloud

## AI Factories

Pre-validated reference architectures:
- Dell AI Factory with NVIDIA
- Cisco Secure AI Factory
- Lenovo Hybrid 221 Microfactory
- Red Hat AI Factory with NVIDIA

## Applicability to RFP Responses

When a customer asks about model serving, inference performance, hardware support, or Model-as-a-Service, reference this document for:
- Supported model list and optimization approach
- Hardware accelerator compatibility matrix
- Distributed inference capabilities (llm-d)
- API management and governance (AI Gateway)
- Cost optimization through model compression
- Multi-cloud deployment flexibility
