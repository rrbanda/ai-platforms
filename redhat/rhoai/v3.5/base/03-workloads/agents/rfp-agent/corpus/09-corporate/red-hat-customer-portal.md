---
title: Red Hat Customer Portal Capabilities
date: 2026-08-19
source: Red Hat Customer Portal documentation, access.redhat.com
product_area: Support, Customer Experience
---

# Red Hat Customer Portal Capabilities

## Overview

| Attribute | Detail |
|-----------|--------|
| URL | https://access.redhat.com |
| Access | Red Hat account (tied to active subscription) |
| Support channels | Web portal + phone (regional numbers) |

---

## Case Management

- Create, track, and escalate support cases via web interface
- Attach diagnostic files (sosreport) at case creation
- Set severity levels (1–4)
- View case history and correspondence
- Management escalation: "Request Management Escalation" button within case interface
- Best practice: attach sosreport at case creation for faster resolution

---

## Knowledgebase

- Solutions: troubleshooting articles for known issues
- Articles: how-to guides and technical references
- Documentation: full product documentation sets
- Search by product, version, topic, or error message

---

## Errata and Security Advisories

- Patch notifications for all subscribed products
- CVE details with severity scoring (CVSS)
- Affected package lists per advisory
- Remediation instructions
- Categories: RHSA (security), RHBA (bug fix), RHEA (enhancement)

---

## Software Downloads

- ISO images for RHEL, Satellite, other products
- Container images via registry.redhat.io
- Software updates (RPMs, errata packages)
- Source RPMs
- Binary downloads for supplementary tools

---

## Red Hat Insights (now Red Hat Lightspeed)

Proactive analytics platform integrated into the Customer Portal.

| Capability | Detail |
|-----------|--------|
| Supported platforms | RHEL, OpenShift, Ansible Automation Platform |
| Vulnerability assessment | CVE scanning with risk-based prioritization |
| Compliance scanning | OpenSCAP-based policy evaluation |
| Configuration drift detection | Baseline comparison across fleet |
| Remediation recommendations | Auto-generated Ansible playbooks |
| AI assistant | Natural language queries for troubleshooting and guidance |

---

## Ecosystem Catalog

- Certified hardware: servers, storage, networking equipment
- Certified software: ISV applications validated on Red Hat platforms
- Certified cloud providers: AWS, Azure, GCP, IBM Cloud
- Searchable by product version, category, vendor

---

## Subscription Management

- View active subscriptions and entitlements
- Allocate subscriptions to systems
- Track consumption and utilization
- Manage system registrations
- Export subscription reports

---

## Product Lifecycle Information

- General Availability (GA) dates
- Full Support phase end dates
- Maintenance Support phase end dates
- Extended Life Cycle Support (ELS) availability
- Extended Update Support (EUS) streams

---

## Labs and Tools

| Tool | Purpose |
|------|---------|
| Product Selector | Guided product recommendation |
| JBoss Migration Toolkit | Application migration analysis |
| Container Health Index | Container image security grading |
| Certificate Tool | SSL/TLS certificate troubleshooting |
| Registration Assistant | System registration guidance |

---

## Support Workflow Best Practices

1. Create case via portal with detailed description
2. Attach sosreport (RHEL) or must-gather (OpenShift) immediately
3. Set appropriate severity level
4. Monitor case for Technical Account Manager or engineer response
5. Use "Request Management Escalation" button if response SLA is at risk
6. Phone support available for Severity 1 cases (regional numbers listed in portal)
