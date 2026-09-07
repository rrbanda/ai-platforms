---
title: Red Hat OpenShift AI platform components
date: 2026-08-24
source: RHOAI field GitOps skill gitops-config-generator (RHOAI 3.5 DSC paths); red-hat-ai-platform-gpu-hybrid.md (workbenches); red-hat-ai-inference-capabilities.md (serving stack)
product_area: Red Hat OpenShift AI
---

# Red Hat OpenShift AI — Platform Components

> Reference for RFI/RFP rows about dashboard, workbenches, pipelines, and operator-managed enablement.
> Do not invent install/upgrade/backup procedures from this page. Those remain `[HUMAN INPUT REQUIRED]` until a lifecycle encyclopedia exists.

## DataScienceCluster

Red Hat OpenShift AI is enabled through a **DataScienceCluster** custom resource (typical name `default-dsc`). Administrators set each component to `Managed`, `Removed`, or `Unmanaged` rather than installing unmanaged Helm charts for those components.

API: `datasciencecluster.opendatahub.io/v1`, kind `DataScienceCluster`.

**Source:** RHOAI field GitOps skill `gitops-config-generator`, RHOAI 3.5 component list.

## RHOAI 3.5 components (DSC paths)

| Component | DSC path | Notes for questionnaires |
|-----------|----------|--------------------------|
| KServe | `.spec.components.kserve.managementState` | Model serving. Enabling KServe expects ServiceMesh and cert-manager. |
| ModelMeshServing | `.spec.components.modelMeshServing.managementState` | Multi-model serving path |
| Dashboard | `.spec.components.dashboard.managementState` | Web console for data science projects |
| Workbenches | `.spec.components.workbenches.managementState` | Data scientist self-service notebooks |
| DataSciencePipelines | `.spec.components.datasciencepipelines.managementState` | Pipeline orchestration |
| Ray | `.spec.components.ray.managementState` | Distributed compute |
| Kueue | `.spec.components.kueue.managementState` | Job queueing / GPU sharing |
| TrustyAI | `.spec.components.trustyai.managementState` | Guardrails / bias / explainability |
| ModelRegistry | `.spec.components.modelregistry.managementState` | Model registry |
| TrainingOperator | `.spec.components.trainingoperator.managementState` | Distributed training |
| FeastOperator | `.spec.components.feastoperator.managementState` | Feature store |
| OGX | `.spec.components.ogx.managementState` | Agent-as-a-Service / Responses API (see naming table) |
| MLflowOperator | `.spec.components.mlflowoperator.managementState` | Experiment tracking |

**Source:** same field skill, table “Component / DSC Path / Dependencies.”

## Workbenches and self-service

Red Hat AI documents **workbenches** as data-scientist self-service on the platform, with GPU pooling and quotas as a shared IT utility.

**Source:** `red-hat-ai-platform-gpu-hybrid.md`, Multi-Tenancy and Governance.

## Serving stack (do not split vLLM out as a Red Hat SKU)

Inference is catalog + **vLLM** (engine inside OpenShift AI) + **llm-d** (distributed inference). See `red-hat-ai-inference-capabilities.md` and `product-naming-canonical.md`.

## What this document does not claim

- Exact OLM Subscription channel names or backup procedures
- That every component is GA (use `component-maturity-table.md`)
- Pricing
