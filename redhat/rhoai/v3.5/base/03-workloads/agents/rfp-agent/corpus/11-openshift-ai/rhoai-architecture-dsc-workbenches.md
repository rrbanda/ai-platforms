---
title: Red Hat OpenShift AI architecture, projects, and DataScienceCluster
date: 2026-08-24
source: Official 3.5 architecture chapter; 3.4/3.5 release notes (DSC / MLflow / KServe)
product_area: Red Hat OpenShift AI
---

# Understanding OpenShift AI architecture and operators

> Reference study guide for: Architecture of OpenShift AI Self-Managed (3.5) plus DataScienceCluster notes in 3.4/3.5 release notes.
> https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/installing_and_uninstalling_openshift_ai_self-managed/architecture-of-openshift-ai-self-managed_install

## Module 1: What the product is

Red Hat OpenShift AI Self-Managed is an **Operator** on:

- Red Hat OpenShift Container Platform
- OpenShift Dedicated (CCS on AWS or GCP)
- ROSA classic or ROSA HCP
- Microsoft Azure Red Hat OpenShift

**Source:** 3.5 architecture chapter, opening paragraphs.

## Module 2: Service layer vs management layer

**Service layer (3.5 architecture):**

| Capability | What the 3.5 architecture chapter says |
|------------|----------------------------------------|
| Dashboard | Customer-facing UI: apps, tutorials, admin of users/clusters/workbench images/serving runtimes; data scientists create **projects** |
| Model serving | Deploy trained models; apps call the deployed API endpoint |
| AI pipelines | Portable ML workflows using Docker containers; automate as models develop |
| Jupyter (self-managed) | Standalone workbench in JupyterLab |
| Distributed workloads | Multi-node parallel train/process; larger datasets |
| RAG | RAG via the integrated **OGX** Operator: LLM inference, semantic retrieval, vector database, project-local datasets |

**Management layer:** The Red Hat OpenShift AI Operator is a **meta-operator** that deploys and maintains components and sub-operators.

```
┌─────────────────────────────────────────────┐
│  OpenShift AI dashboard / projects          │
├─────────────┬─────────────┬─────────────────┤
│ Workbenches │ Pipelines   │ Model serving   │
│ Jupyter     │ AI pipelines│ KServe / llm-d  │
├─────────────┴─────────────┴─────────────────┤
│ OGX (RAG / Responses API)                   │
├─────────────────────────────────────────────┤
│ Red Hat OpenShift AI Operator (meta)        │
└─────────────────────────────────────────────┘
```

**Source:** 3.5 architecture chapter, service layer and management layer.

## Module 3: Default projects

When installed with predefined projects:

| Project | Role |
|---------|------|
| `redhat-ods-operator` | OpenShift AI Operator |
| `redhat-ods-applications` | Dashboard and required components |
| `rhods-notebooks` | Default basic workbenches |

Custom projects are allowed. Data scientists need additional projects for applications that consume models. **Do not install ISV applications in OpenShift AI-associated namespaces.**

**Source:** 3.5 architecture chapter, project list.

## Module 4: DataScienceCluster (from release notes)

Administrators enable components with `managementState: Managed` (or Removed / Unmanaged) on the **DataScienceCluster** CR.

Examples called out in 3.4/3.5 notes:

- `mlflowoperator` — managed starting **3.4**; dashboard MLflow follows component state; deprecated `mlflow` dashboard flag is no longer required.
- `spec.components.kserve.oauthProxy.resources` — 3.5 EA2: OAuth proxy sidecar CPU/memory without flipping KServe to Unmanaged.

**Source:** 3.4 notes “MLflow Operator is now a managed component”; 3.5 EA2 “OAuth proxy sidecar … DataScienceCluster API”.

## Module 5: Workbenches (notes)

- Default workbench images include TensorFlow and PyTorch; GPUs and Intel Gaudi are documented accelerators in the 3.3 overview.
- **Hardware profiles** are GA from 3.0 (reiterated in 3.3): target worker nodes for workbenches, serving, and pipelines; they replace deprecated accelerator profiles.
- 3.4: granular RBAC for workbenches via labeled Kubernetes Roles; MLflow SDK auto-config via annotation `opendatahub.io/mlflow-instance`.
- 3.5: MLflow SDK pre-installed in datascience, tensorflow, pytorch, and codeserver images.

**Source:** 3.3 overview + hardware profiles GA; 3.4 workbench RBAC and MLflow annotation; 3.5 workbench image notes.
