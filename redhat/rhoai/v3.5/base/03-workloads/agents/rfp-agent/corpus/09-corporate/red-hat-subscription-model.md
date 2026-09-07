---
title: Red Hat Subscription Model
date: 2026-08-19
source: Red Hat subscription documentation, pricing guides, customer portal
product_area: commercial
---

# Red Hat Subscription Model

## Fundamental Model

Red Hat subscriptions are **not software licenses**. All Red Hat product source code is open source and freely available. A subscription provides:

- Software updates and security errata
- Certified, tested platform binaries
- Technical support (tier-dependent)
- Access to Red Hat Customer Portal and knowledgebase
- Red Hat Insights (operational analytics)
- Legal assurance and intellectual property protection

## Pricing Dimensions

| Dimension | Options |
|---|---|
| Subscription unit | Socket-pair, cores, or per-node (varies by product) |
| Support tier | Self-Support, Standard, Premium |
| Term length | 1-year or 3-year |

Multi-year commitments (3-year terms) provide price protection over the term and volume leverage in enterprise agreements.

## Deployment Models

| Model | Unit | Use Case |
|---|---|---|
| Physical | Per socket-pair | Bare-metal servers |
| Virtual Datacenter | Per hypervisor host (unlimited VMs) | Dense virtualization environments |
| Virtual | Per guest VM | Individual virtual machines |
| Cloud | Per instance or per core | Public cloud deployments (AWS, Azure, GCP) |

## Product Subscription Types

| Product | Unit | Notes |
|---|---|---|
| Red Hat Enterprise Linux (RHEL) | Per socket-pair or per instance | Physical, virtual, and cloud options |
| Red Hat OpenShift | Per core (2 vCPU = 1 core) | Includes RHEL CoreOS entitlement |
| Red Hat Ansible Automation Platform | Per managed node | Controller infrastructure included |

## Extended Lifecycle Options

| Option | Description |
|---|---|
| EUS (Extended Update Support) | Locks a minor release for up to 24 months of additional updates beyond standard support |
| ELS (Extended Life Cycle Support) | Extends critical/important security fixes beyond End of Life for a major version |

## Developer Subscription

| Field | Detail |
|---|---|
| Cost | Free |
| Systems | Up to 16 |
| Support tier | Self-Support only |
| Use case | Development, testing, prototyping |

## Subscription Lapse Behavior

If a subscription lapses:

- Software continues to run (no kill switch)
- No further updates or security errata
- No access to technical support
- System falls out of certified/validated configuration
- Compliance posture may be affected (no FIPS/STIG updates)

## Enterprise Agreements

As an IBM subsidiary, Red Hat subscriptions can be bundled into IBM enterprise agreements. This enables:

- Consolidated procurement across IBM and Red Hat products
- Volume pricing across the combined portfolio
- Single commercial relationship for hybrid cloud + automation + AI

## No Lock-In

Red Hat subscriptions carry no vendor lock-in:

- All product source code is open source
- Standard APIs and protocols (Kubernetes, Ansible, Linux)
- Multi-cloud portability (AWS, Azure, GCP, on-premises)
- Data formats are open and documented
- Customers can rebuild from source at any time
