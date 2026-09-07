---
title: Red Hat Security Practices
date: 2026-08-19
source: Red Hat 2025 Product Security Risk Report, PSIRT documentation, security portal
product_area: security
---

# Red Hat Security Practices

## Product Security Incident Response Team (PSIRT)

Red Hat PSIRT has been active since 2001. The team oversees vulnerability management across **400,000+ components and versions** in supported products.

## Vulnerability Management Workflow

The vulnerability lifecycle follows three phases:

1. **Assessment** — Triage incoming reports, determine affected products and versions, assign CVSS score, classify severity
2. **Remediation** — Develop fixes, backport to supported release streams, build and test errata
3. **Response** — Publish advisory, push errata to customer portals, update CVE database entries

## CVE Response Times (2025 Risk Report)

| Severity | Average Time to Fix | Volume (2025) |
|---|---|---|
| Critical | 12 days | 3 CVEs total |
| Important | 24 days | — |
| Moderate | 79 days | — |

## Fix Coverage by Severity

| Severity | Fix Policy |
|---|---|
| Critical | Fixed across all supported versions |
| Important | Fixed across all supported versions |
| Moderate (CVSS > 7.0) | Addressed in supported versions |
| Moderate (CVSS ≤ 7.0) | Deferred to next major release unless known exploit exists |
| Low | Deferred to next major release unless known exploit exists |

## Coordinated Vulnerability Disclosure

| Field | Detail |
|---|---|
| Contact | secalert@redhat.com |
| Encryption | PGP-encrypted submissions accepted |
| Embargo preference | Less than 14 days |
| Public disclosure | All CVE information published immediately after assessment completes (unless under active embargo) |

## Machine-Readable Advisories

Since July 2024, Red Hat publishes advisories in **CSAF (Common Security Advisory Framework)** and **VEX (Vulnerability Exploitability eXchange)** formats. These enable automated ingestion by vulnerability management tools and SBOMs.

## Incident Response

Red Hat maintains a documented **Incident Response Plan (IRP)** that defines:

- Roles and responsibilities for security incidents
- Escalation procedures and communication protocols
- Post-incident review and remediation tracking
- Coordination with upstream communities and affected vendors

## Security Portal

The Red Hat Security portal provides public access to:

- CVE database with Red Hat-specific impact assessments
- Security advisories (RHSA, RHBA, RHEA)
- OVAL and CSAF data feeds
- Vulnerability metrics and risk reports

URL: [https://access.redhat.com/security](https://access.redhat.com/security)
