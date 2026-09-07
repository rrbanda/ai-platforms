---
title: Red Hat Compliance Certifications
date: 2026-08-19
source: Red Hat trust center, compliance documentation, NIST CMVP records
product_area: governance
---

# Red Hat Compliance Certifications

## Audit Status

The 2026 consolidated audit completed with **zero findings** across all in-scope certifications.

## Certifications and Attestations

| Certification | Scope | Notes |
|---|---|---|
| ISO 27001 | Managed services (OpenShift Dedicated, Quay.io, RHACS Cloud Service) | Information security management |
| ISO 27017 | Managed services | Cloud-specific security controls |
| ISO 27018 | Managed services | PII protection in public cloud |
| SOC 1 Type 2 | Managed services | Financial reporting controls |
| SOC 2 Type 2 | Managed services | Security, availability, confidentiality |
| SOC 3 | Managed services | Public-facing trust report |
| PCI-DSS v4.0.1 | Applicable managed services | Payment card data handling |
| HIPAA | Applicable managed services | Healthcare data safeguards |
| CSA STAR Level 2 | Managed services | Cloud Security Alliance certification |
| FFIEC | Applicable services | Financial institution compliance |

## Government and Defense

| Certification | Scope | Notes |
|---|---|---|
| FedRAMP High | Red Hat OpenShift Service on AWS (ROSA) | US federal workloads at High impact level |
| Common Criteria (ISO/IEC 15408) | Specific RHEL versions | Evaluated assurance level for OS |
| DISA STIG | RHEL, OpenShift | Security Technical Implementation Guides; profiles available via OpenSCAP automation |
| CIS Benchmarks | RHEL | Available via scap-security-guide |

## Cryptographic Validation

| Standard | Status | Notes |
|---|---|---|
| FIPS 140-2 | Validated modules for RHEL | Moving to NIST historical list on September 21, 2026 |
| FIPS 140-3 | Validated modules for RHEL | Current standard; active validation |

FIPS 140-2 validated modules will be placed on the NIST historical list effective September 21, 2026. Organizations requiring active FIPS validation should migrate to FIPS 140-3 validated configurations.

## AI Governance

Red Hat is aligning AI software practices with **ISO 42001** (Artificial Intelligence Management System) for responsible AI development, deployment, and operations.

## EU Regulatory Alignment

| Regulation | Red Hat Coverage |
|---|---|
| NIS2 (Network and Information Security Directive) | RHEL hardening, Ansible compliance automation |
| DORA (Digital Operational Resilience Act) | RHEL, OpenShift operational resilience controls |
| CRA (Cyber Resilience Act) | RHEL supply chain provenance, SBOM generation |

## Shared Responsibility Model

Compliance is a shared responsibility:

- **Red Hat provides:** validated, certified platform components; hardened default configurations; security errata; compliance content (SCAP profiles, STIG guides)
- **Customer responsible for:** integrated system configuration, access control policies, data classification, application-level compliance, audit evidence for their deployments
