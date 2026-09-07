# Ansible Automation Platform 2.7 — Compliance Dashboard & Security Automation

## Overview

Red Hat Ansible Automation Platform (AAP) 2.7 includes a built-in Compliance Dashboard that provides an end-to-end compliance experience: scanning infrastructure against industry standards, reviewing per-host findings, and executing targeted remediation — all from within the Ansible Portal. No additional agents or external scanning tools are required.

## In-Platform Compliance Dashboard

### Supported Compliance Profiles

| Standard | Coverage |
|----------|----------|
| **DISA STIG** | Defense Information Systems Agency Security Technical Implementation Guides |
| **CIS Benchmarks** | Center for Internet Security Level 1 and Level 2 |
| **PCI-DSS** | Payment Card Industry Data Security Standard |
| **OpenSCAP** | Security Content Automation Protocol profiles |
| **Custom Profiles** | Organization-specific security baselines |

### Key Features

- **Agentless scanning**: No agents required on target hosts — uses SSH/WinRM
- **Scalable**: Scan thousands of hosts in parallel
- **Continuous monitoring**: Scheduled scans for drift detection
- **Audit-grade results**: Scanner output suitable for compliance certification audits
- **Per-host findings**: Drill into individual system compliance status
- **Severity classification**: Critical → Low priority categorization

### Granular Remediation Builder

The remediation builder provides precision control:

- **Per-rule toggles**: Enable or disable remediation for individual findings
- **Parameter customization**: Adjust remediation parameters per organizational policy
- **Host-level targeting**: Apply fixes to specific hosts or groups
- **Powered by Compliance-As-Code**: Content from the trusted RHEL supply chain (SCAP Security Guide)

## Closed-Loop Remediation Workflow

```
1. Define compliance profile (DISA STIG, CIS Level 1/2, PCI-DSS)
2. Select host inventory
3. Run agentless scan
4. Review findings by severity (Critical → Low)
5. Toggle individual rules for remediation
6. Execute targeted remediation playbook
7. Re-scan to verify compliance
8. Export audit-grade report
```

## Security Automation Capabilities

### Self-Service Security Templates (AAP 2.7 Automation Portal)

Pre-built templates for common security operations:

| Category | Templates |
|----------|-----------|
| **Security Patching** | CVE Patch, RHEL Patch Servers (Maintenance Window) |
| **Network Security** | Firewall Remediation, Firewall Rule Request, Backup Switch Configs |
| **Credential Management** | Rotate Secrets, Revoke Access, Update Certificates |
| **Incident Response** | Quarantine Host, Disable Account, Block IP |

### Approval-Gated Workflows

- RBAC separation of duties (requester ≠ approver)
- Multi-level approval chains for production changes
- Immutable audit trail of all approvals and executions
- Integration with ITSM for change management compliance

### Event-Driven Automation for Security

- Trigger playbooks automatically on SIEM alerts, scanner findings, or API events
- Condition-based rulebooks evaluate severity and context before action
- Sub-second response time for containment actions
- Human-in-the-loop gates for destructive operations

## OpenSCAP Integration

Two approaches to compliance remediation:

1. **Generated from scan results**: Playbook contains only tasks for rules that failed on this specific system — targeted, minimal-change approach
2. **Pre-built SSG playbooks**: Applies all rules in the profile regardless of current state — full-profile hardening for new deployments

## Integration with Red Hat Insights

- Red Hat Insights detects vulnerabilities and compliance gaps
- Automatically generates remediation playbooks
- Execute via Cloud Connector (up to 100 systems) or AAP for enterprise scale
- Track remediation status: Pending → Running → Success → Failure

## Enterprise Security Features

- **Signed automation content**: Playbooks cryptographically signed for trust verification
- **Execution Environments**: Containerized, immutable runtime for consistent behavior
- **Credential management**: Vault integration (HashiCorp, CyberArk, Azure Key Vault) with OIDC
- **Role-Based Access Control**: Granular permissions for who can view, edit, execute, approve
- **Audit logging**: Every action captured with timestamp, user, and outcome

## Metrics & Evidence for Governance

- Compliance score per host, per profile, per organizational unit
- Trend analysis showing improvement over time
- Exportable reports for auditors (PDF, CSV, API)
- Evidence of remediation: before/after scan results with timestamps

## Source

Based on Ansible Automation Platform 2.7 documentation, AnsiblePilot In-Platform Compliance Dashboard article (May 2026), Red Hat Tech Day Netherlands 2026 demos, and Red Hat Lightspeed remediation workflow documentation.
