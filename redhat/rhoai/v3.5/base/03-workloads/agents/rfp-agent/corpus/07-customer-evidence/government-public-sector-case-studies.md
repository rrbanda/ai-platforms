---
title: "Government & Public Sector Case Studies"
date: 2026-08-19
source: "Red Hat customer success stories, FedRAMP marketplace, DISA STIG library"
product_area: "customer-evidence-government"
---

# Government & Public Sector Case Studies

## CalHEERS — California Health Benefit Exchange

| Metric | Value |
|---|---|
| Population served | 17 million Californians |
| Peak daily transactions | 91 million |
| Response time improvement | 10% faster |
| Instance provisioning | 15 seconds (down from 15 minutes) |
| 2025 enrollment | 1.97 million |

- **Platform:** Red Hat OpenShift for microservices migration.
- **Migration context:** Legacy monolithic platform originally deployed in 2012. Migrated to container-based microservices architecture on OpenShift.
- **Workloads:** Medi-Cal eligibility determination, Covered California health plan enrollment, real-time benefits calculation.
- **Scale:** Handles annual open enrollment surges with auto-scaling on OpenShift. Peak load occurs during November–January enrollment window.

## ODC-Noord — Netherlands Government Cloud

| Metric | Value |
|---|---|
| Organizations served | 48 |
| Ministries covered | 11 |
| IaaS platform live since | 2016 |
| OpenShift foundation since | 2018 |

- **Platform:** Sovereign government cloud infrastructure built on Red Hat OpenShift.
- **Use case:** Provides shared IT infrastructure services to Dutch government organizations. Data remains within Dutch jurisdiction.
- **Architecture:** Multi-tenant OpenShift clusters with namespace-level isolation per organization. Shared CI/CD pipelines, centralized logging, and monitoring.

## Public Health Authority of Frankfurt

| Detail | Value |
|---|---|
| Platform | Red Hat OpenShift (managed by VSHN) |
| Application | GA-Lotse platform modernization |
| Year | 2026 |

- Standardized on Red Hat OpenShift for public health application hosting.
- **GA-Lotse:** Digital health services platform serving Frankfurt metropolitan area.
- Federated access control with integration to German eID infrastructure.
- Encryption at rest and in transit for all health data.
- Managed by VSHN (Swiss/European OpenShift managed service provider).

## FedRAMP Compliance

- **Red Hat OpenShift Service on AWS (ROSA):** Approved for **FedRAMP High** authorization level.
- FedRAMP High covers the most sensitive unclassified government data (law enforcement, financial, healthcare).
- ROSA inherits AWS GovCloud physical and network controls; Red Hat maintains authorization for the OpenShift platform layer.

## DISA STIG Compliance

- Red Hat provides **DISA STIG** (Security Technical Implementation Guide) compliance content via **OpenSCAP** and the **scap-security-guide** package.
- Automated scanning and remediation for RHEL, OpenShift, and Ansible.
- STIG profiles ship in the base RHEL and OpenShift installations — no additional tooling required.
- Continuous compliance monitoring integrates with Red Hat Insights.

## Air-Gapped Deployment

- Red Hat OpenShift supports fully **air-gapped (disconnected) installation** for classified and restricted environments.
- Mirror registry pattern: operator catalogs and container images are mirrored to a local registry with no external network access.
- Lifecycle management (upgrades, patching) supported in disconnected mode via oc-mirror tooling.
- Validated for SCIF (Sensitive Compartmented Information Facility) and similar restricted environments.
