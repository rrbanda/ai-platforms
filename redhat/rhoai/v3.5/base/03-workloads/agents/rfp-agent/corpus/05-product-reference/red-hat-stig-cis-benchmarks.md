---
title: Red Hat STIG & CIS Benchmark Coverage
date: 2026-08-19
source: DISA STIG documentation, CIS Benchmarks, Red Hat security guides
product_area: Security, Compliance
---

# Red Hat STIG & CIS Benchmark Coverage

## DISA STIG (Security Technical Implementation Guides)

STIGs are configuration standards published by the Defense Information Systems Agency for US DoD systems.

### Platform Coverage

| Platform | STIG Available | Automated Profile |
|----------|---------------|-------------------|
| RHEL 7 | Yes | scap-security-guide |
| RHEL 8 | Yes | scap-security-guide |
| RHEL 9 | Yes | scap-security-guide |
| RHEL 10 | Yes | scap-security-guide |
| OpenShift Container Platform | Yes | Compliance Operator |

### Automation

- Automated application via OpenSCAP (`oscap`) tool
- `scap-security-guide` package ships STIG profiles out of the box
- Remediation scripts generated automatically from scan results
- Kickstart integration for STIG-hardened installations
- Ansible remediation playbooks included in scap-security-guide

---

## CIS Benchmarks (Center for Internet Security)

### Profile Levels

| Level | Description | Use Case |
|-------|-------------|----------|
| Level 1 | Basic security, minimal performance impact | General-purpose servers |
| Level 2 | Stringent security, potential performance impact | High-security environments |

### Coverage

- CIS Benchmark profiles for RHEL shipped in `scap-security-guide`
- Automated scanning and reporting via OpenSCAP
- Both Level 1 and Level 2 profiles available
- Remediation scripts generated from scan findings

---

## OpenSCAP

Open source implementation of the Security Content Automation Protocol (SCAP).

| Attribute | Detail |
|-----------|--------|
| Availability | Part of every RHEL installation |
| Package | `openscap-scanner` |
| License | Open source (LGPL) |
| Standards supported | XCCDF, OVAL, DataStream, ARF |

### Tools

| Tool | Purpose |
|------|---------|
| `oscap` CLI | Command-line scanning and remediation |
| `scap-workbench` | GUI for profile selection and scanning |
| Red Hat Satellite integration | Fleet-wide scanning and reporting |

### CLI Usage

```
oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_stig \
  --results scan-results.xml \
  --report scan-report.html \
  /usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml
```

---

## Compliance Operator for OpenShift

Kubernetes operator that runs OpenSCAP on cluster nodes continuously.

| Attribute | Detail |
|-----------|--------|
| Deployment | Operator installed via OperatorHub |
| Scanning | Runs OpenSCAP on every node |
| Monitoring | Continuous compliance monitoring |
| Remediation | Auto-remediates findings per policy configuration |
| Reporting | ComplianceScan and ComplianceCheckResult CRDs |

### Supported Profiles

- STIG (DoD systems)
- CIS Benchmarks (Level 1 and Level 2)
- Custom profiles (user-defined)
- PCI-DSS
- HIPAA (via custom tailoring)

### Architecture

1. `ComplianceSuite` CR defines which profiles to apply
2. `ScanSetting` CR defines scan schedule and node targeting
3. Operator schedules `ComplianceScan` pods on each node
4. Results stored as `ComplianceCheckResult` CRs
5. `ComplianceRemediation` CRs generated for failed checks
6. MachineConfig updates applied automatically if auto-remediation enabled

---

## Red Hat Satellite

Fleet-wide compliance management for RHEL systems.

| Capability | Detail |
|-----------|--------|
| Fleet scanning | Schedule and run OpenSCAP scans across all managed hosts |
| Policy enforcement | Define and apply compliance policies by host group |
| Drift detection | Compare current state against baseline across environments |
| Reporting | Compliance reports per host, host group, or policy |
| Remediation | Generate and apply Ansible remediation playbooks |

---

## Compliance as Code

OpenSCAP profiles are maintained in the upstream ComplianceAsCode project.

| Attribute | Detail |
|-----------|--------|
| Repository | github.com/ComplianceAsCode/content |
| Contributors | Red Hat, DISA, CIS, community |
| Output formats | XCCDF, OVAL, Ansible, Bash, Kickstart |
| Release mechanism | Shipped via `scap-security-guide` RPM |
| Update frequency | Aligned with DISA STIG quarterly releases |

---

## Compliance Workflow Summary

| Environment | Tool | Automation |
|-------------|------|-----------|
| Single RHEL host | `oscap` CLI | Manual or cron |
| RHEL fleet | Red Hat Satellite | Scheduled, policy-based |
| OpenShift cluster | Compliance Operator | Continuous, auto-remediation |
| CI/CD pipeline | `oscap` in container | Per-build scanning |
