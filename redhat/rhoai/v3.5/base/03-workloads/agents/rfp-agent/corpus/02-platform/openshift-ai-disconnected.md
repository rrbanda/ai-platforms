---
title: Red Hat OpenShift AI disconnected and GPU pooling
date: 2026-08-24
source: red-hat-ai-platform-gpu-hybrid.md; government-public-sector-case-studies.md; RHOAI field skill rhoai-disconnected-helper
product_area: Red Hat OpenShift AI
---

# Red Hat OpenShift AI — Disconnected Deployments and GPU Pooling

> Use for RFI rows on air-gap, oc-mirror, and Kueue. Do not invent a site-specific mirror registry design.

## Disconnected / air-gapped

Red Hat AI documents air-gapped deployments:

- Mirror container images to an internal registry
- Offline model catalog
- No external network dependencies at runtime
- Relevant for defense, government, and regulated industries

**Source:** `red-hat-ai-platform-gpu-hybrid.md`, section Disconnected / Air-Gapped Support.

OpenShift (the platform under OpenShift AI) supports fully air-gapped install: operator catalogs and images mirrored to a local registry; upgrades and patching via **oc-mirror**.

**Source:** `government-public-sector-case-studies.md`, Air-Gapped Deployment.

Field practice for OpenShift AI on a disconnected cluster additionally checks:

- ImageDigestMirrorSet (IDMS) and ImageTagMirrorSet (ITMS)
- Pull secret validity and CA trust bundles
- A custom CatalogSource (not `redhat-operators`) pointing at the disconnected index
- That the RHOAI Subscription `source` uses that CatalogSource
- All images used by OpenShift AI must be mirrored, not only the operator

**Source:** RHOAI field skill `rhoai-disconnected-helper`. Site-specific mirror hostnames remain `[HUMAN INPUT REQUIRED]`.

## GPU pooling and Kueue

Red Hat AI treats GPUs as a shared utility: cluster-wide pool, dynamic scale/slice using **Kueue** and InstaSlice, request prioritization, inference-aware autoscaling.

Kueue is also a DataScienceCluster component (`.spec.components.kueue.managementState`).

**Source:** `red-hat-ai-platform-gpu-hybrid.md`; `openshift-ai-components.md`.

## What this document does not claim

- A particular disconnected customer’s registry URL or CatalogSource name
- Node Feature Discovery or GPU Operator step-by-step install (not sourced here)
- List price per GPU-hour
