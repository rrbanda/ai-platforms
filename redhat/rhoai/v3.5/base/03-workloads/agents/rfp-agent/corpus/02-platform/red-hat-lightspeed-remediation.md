# Red Hat Lightspeed — AI-Driven Vulnerability Remediation at Scale

## Overview

Red Hat Lightspeed (formerly Red Hat Insights) integrates AI-driven vulnerability management with automated Ansible Playbook generation and execution. It enables organizations to scan, prioritize, and remediate RHEL vulnerabilities and compliance gaps across their entire infrastructure — saving up to 86% of manual remediation time.

## Core Capabilities

### Vulnerability Scanning & Assessment

- **Agentless discovery**: Insights client gathers system data and uploads to vulnerability service
- **Red Hat CVE database cross-reference**: Compares installed packages against known vulnerabilities
- **Continuous monitoring**: Daily automated scans detect newly-published CVEs affecting your fleet
- **No additional tooling**: Included with existing RHEL, AAP, and OpenShift subscriptions

### Intelligent Prioritization

| Filter | Description |
|--------|-------------|
| **Severity** | Critical, Important, Moderate, Low (Red Hat's four-point scale) |
| **CVSS Score** | Numerical scoring for granular ordering |
| **Known Exploits** | CVEs with confirmed public exploits (highest urgency) |
| **Business Risk** | User-assigned risk levels for organizational context |
| **Fixability** | Whether a patch/errata is currently available |
| **EPSS** | Exploit prediction probability score |

### AI-Powered Remediation (MCP Integration)

Red Hat Lightspeed MCP enables natural language vulnerability management:

| Workflow | Example Prompt |
|----------|---------------|
| **Urgent patch identification** | "Show me all critical vulnerabilities (CVSS > 8) without patches applied" |
| **Specific exploit exposure** | "Which systems are exposed to CVE-2021-4034 and generate a remediation playbook?" |
| **Risk group assessment** | "What are the top 5 most critical CVEs affecting my infrastructure?" |
| **Threat actor focus** | "Find all vulnerabilities actively being exploited that affect my systems" |
| **Prioritization** | "Prioritize vulnerabilities for staging systems based on severity and exploitability" |
| **Minimal downtime** | "Which vulnerabilities can be fixed without requiring a reboot?" |
| **Compliance reporting** | "Which systems are non-compliant with our 30-day patching policy for CVSS > 7?" |

## Automated Remediation Workflow

### Plan Creation

1. Navigate to Vulnerability, Advisor, or Compliance service
2. Select one or more CVEs/recommendations across multiple systems
3. Click "Plan remediation" → generates Ansible Playbook automatically
4. Name the plan (e.g., "August 2026 Critical Patches")
5. Review affected systems and planned actions

### Execution

**Direct execution** (Red Hat Lightspeed → connected systems):
- Supported for plans up to **100 systems** and **1,000 action points**
- Pre-flight execution readiness checks verify connectivity and permissions
- Real-time status tracking: Pending → Running → Success → Failure

**Enterprise-scale execution** (via Ansible Automation Platform):
- For plans exceeding Lightspeed guardrails
- Advanced scheduling, RBAC, and auditing
- Integration with approval workflows
- Supports thousands of systems simultaneously

### Post-Execution Tracking

- Remediation status tracked per system, per CVE
- Dashboard shows remaining exposure after remediation
- Re-scan validates successful closure
- Evidence exportable for audit requirements

## Scalability Guardrails

Red Hat Lightspeed uses an action-point system to ensure reliable execution:

- Each remediation action has a calculated complexity score
- Plans guaranteed to execute reliably up to **1,000 action points** and **100 systems**
- Visual representation of plan complexity in the Planned Remediations tab
- Seamless handoff to Ansible Automation Platform for larger operations

## CVE Status Management

For findings that don't require patching:

| Status | Use Case |
|--------|----------|
| **No action — risk accepted** | Business decision to accept residual risk |
| **Resolved via mitigation** | Compensating control in place |
| **Not applicable** | System configuration makes vulnerability unexploitable |

Each status requires a business justification, maintaining audit readiness.

## Integration Architecture

```
RHEL Systems (Insights Client) → Red Hat Hybrid Cloud Console
    → Vulnerability Service (CVE cross-reference)
    → Remediation Planner (Ansible Playbook generation)
    → Execution Engine (direct or via AAP)
    → Verification (re-scan)
```

## Key Metrics

- **86% reduction** in manual remediation time
- **Minutes**: Time from CVE identification to playbook execution
- **100% traceability**: Every action from scan to remediation to verification is logged
- **Zero manual playbook writing**: Playbooks auto-generated from Red Hat's CVE knowledge

## Applicability to Enterprise Remediation Programs

For organizations managing thousands of findings across multiple portfolios:

1. **Assessment & Triage**: Lightspeed scans provide the vulnerability baseline
2. **Prioritization**: EPSS + known-exploit filters identify highest-risk items
3. **Remediation Execution**: Auto-generated playbooks applied at scale
4. **Evidence**: Before/after scan results with timestamps for audit
5. **Governance**: Dashboard tracks burn-down across waves
6. **KPIs**: Cycle time, closure rate, and rework metrics built in

## Source

Based on "Tackle critical vulnerabilities with the new Red Hat Lightspeed remediation workflow" (Red Hat Blog, 2026), "Find and fix RHEL vulnerabilities with Red Hat Lightspeed MCP" (Red Hat Developer, January 2026), and Red Hat Insights documentation.
