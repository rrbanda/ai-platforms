---
title: Red Hat OpenShift AI disconnected installation (official 3.5)
date: 2026-08-24
source: Official 3.5 disconnected install chapter
product_area: Red Hat OpenShift AI
---

# Understanding disconnected OpenShift AI installs

> Reference study guide for: Deploying OpenShift AI in a disconnected environment (Self-Managed 3.5).
> https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/installing_and_uninstalling_openshift_ai_self-managed_in_a_disconnected_environment/deploying-openshift-ai-in-a-disconnected-environment_install

Site-specific registry hostnames remain `[HUMAN INPUT REQUIRED]`.

## Module 1: What “disconnected” means here

Disconnected clusters sit on a restricted network and **cannot** reach Red Hat OperatorHub remote registries. The OpenShift AI Operator is installed after **mirroring images to a private registry**.

High-level sequence in the 3.5 chapter:

1. Confirm cluster requirements
2. Mirror images to a private registry
3. Install the Red Hat OpenShift AI Operator
4. Install OpenShift AI components
5. Component-specific configuration
6. Configure user and administrator groups
7. Give users the dashboard URL

**Source:** 3.5 disconnected chapter, intro and numbered task list.

## Module 2: Platform requirements (3.5 disconnected book)

- Subscription for **Red Hat OpenShift AI Self-Managed** (commercial SKU/price: human).
- Cluster administrator access.
- Supported OpenShift for this chapter: **OpenShift Container Platform 4.19 to 4.20** (see Installing a cluster in a disconnected environment). OpenShift Kubernetes Engine (OKE) is listed with a **licensing exception** for Operators that support OpenShift AI workloads only.
- **Distributed Inference with llm-d** requires the cluster to be **4.20 or later**.
- After cluster install, configure Cluster Samples Operator for a restricted cluster.
- On OpenShift **4.21 and later**, OLMv1 catalog is enabled by default as Technology Preview; NFD or NVIDIA GPU Operator installs may land on ClusterExtensions — disable OLMv1 catalog to restore the standard OperatorHub form.
- OpenStack / CRC / private cloud without integrated DNS: configure DNS A/CNAME after LoadBalancer IP is available.
- Minimum **2 worker nodes**, **8 CPUs and 32 GiB RAM each** (Operator install). Single-node OpenShift: **32 CPUs and 128 GiB RAM**.
- **Open Data Hub must not be installed** on the cluster.
- Default StorageClass with dynamic provisioning.

**Source:** 3.5 disconnected chapter, §3.1 Requirements.

> **Key Insight:** An RFI “yes, air-gapped” is not enough. Official 3.5 text requires image mirroring, a private registry, and (for llm-d) OpenShift 4.20+.

## Module 3: OKE exception Operators (do not over-claim OKE support)

The 3.5 table lists Operators that are **not supported on OKE** but may be installed **only** under the OpenShift AI licensing exception:

| OpenShift AI version | Operators (unsupported on OKE; exception required) |
|----------------------|-----------------------------------------------------|
| 2.x | Authorino, Service Mesh, Serverless |
| 3.x | Job-set-operator, custom metrics autoscaler, cert-manager, Leader Worker Set, Connectivity Link, Kueue (RHBOK), SR-IOV, GPU Operator (custom configs), OpenTelemetry, Tempo, Cluster Observability Operator, IBM Spyre Operator |

Using those Operators for **non-OpenShift AI** purposes on OKE violates the OKE agreement per this chapter.

**Source:** 3.5 disconnected chapter, OKE exception table.

## Module 4: llm-d extra Operators (connected or disconnected)

The same chapter notes that deploying models with Distributed Inference with llm-d needs:

- cert-manager Operator
- Red Hat Connectivity Link Operator
- Red Hat Leader Worker Set Operator

**Source:** 3.5 disconnected chapter, llm-d prerequisite bullets.
