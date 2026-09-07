# Request for Proposal
## AI Vulnerability Remediation and AI Security Engineering Services

**Issuing Organization:** Meridian Capital Group  
**Document Reference:** PROC-2026-AI-SEC-0042  
**Document Type:** RFP / Narrative Proposal  
**Deadline:** 2026-10-31  
**Confidentiality:** This document is confidential and proprietary to Meridian Capital Group.

---

## 1. Company Background

Meridian Capital Group is a leading global financial services holding company providing clearing, settlement, and risk management services for capital markets across 18 countries. With over $4.2 trillion in daily transaction volume and 35,000 employees, Meridian is classified as a Systemically Important Financial Market Infrastructure (SIFMI) by the Financial Stability Board.

Meridian operates a hybrid cloud environment with 12,000+ containerized applications running on Red Hat OpenShift across on-premises data centers (New York, London, Singapore) and AWS GovCloud. The organization is subject to SEC Rule 18a-5, FINRA, PCI DSS v4.0.1, SOC 2 Type II, and EU DORA requirements.

Meridian has begun deploying large language models for trade surveillance, regulatory reporting automation, and customer communication analysis. These AI/ML workloads introduce new attack surfaces that our current security operations are not equipped to address.

---

## 2. Project Objective

Meridian seeks proposals from qualified suppliers for the provision of:

1. **AI Vulnerability Assessment and Remediation Services** — Continuous identification, prioritization, and remediation of vulnerabilities across our AI/ML platform, model serving infrastructure, and container supply chain.

2. **AI Security Engineering Services** — Design and implementation of security controls for our GenAI workloads, including model input/output guardrails, prompt injection defense, adversarial red teaming, and secure model lifecycle management.

3. **AI Governance and Compliance Framework** — Establishment of responsible AI practices, model risk documentation, audit trails, and regulatory reporting aligned with SEC, FINRA, and EU AI Act requirements.

---

## 3. Scope of Work

### 3.1 AI Vulnerability Remediation

The supplier shall provide:

- Continuous vulnerability scanning and prioritization for container images, model serving endpoints, and AI pipeline components
- Automated remediation workflows integrated with our existing Ansible Automation Platform
- SBOM generation and VEX advisory management for AI model artifacts
- CVSS and EPSS-based risk scoring with remediation SLA tracking
- Integration with our existing RHACS (Red Hat Advanced Cluster Security) deployment
- Disconnected / air-gapped scanning capability for our sovereign cloud environments

### 3.2 AI Security Engineering

The supplier shall design and implement:

- Runtime guardrails for LLM inputs and outputs (content filtering, PII detection, financial data masking)
- Adversarial red teaming using industry-standard tools (Garak or equivalent) for pre-production model assessment
- Prompt injection and jailbreak defense mechanisms
- Secure model deployment pipelines with cryptographic signing and attestation
- Network segmentation and zero-trust architecture for AI inference endpoints
- Model access control with RBAC, audit logging, and token-level usage tracking

### 3.3 AI Governance

The supplier shall establish:

- Model risk inventory with lineage tracking from training data to production deployment
- Automated compliance documentation for SEC/FINRA regulatory examinations
- Responsible AI review process (bias detection, fairness metrics, explainability reports)
- Model performance monitoring with drift detection and automated retraining triggers
- Integration with MLflow or equivalent experiment tracking platform

---

## 4. Technical Requirements

| ID | Requirement | Priority |
|----|------------|----------|
| T1 | Solution must run on Red Hat OpenShift 4.18+ in disconnected environments | Must Have |
| T2 | Must integrate with Red Hat Advanced Cluster Security (RHACS) for container vulnerability scanning | Must Have |
| T3 | Must support GPU-accelerated model serving with vLLM on NVIDIA and AMD accelerators | Must Have |
| T4 | Must provide runtime AI guardrails (input/output validation, toxicity filtering, PII masking) | Must Have |
| T5 | Must include pre-production adversarial red teaming capability | Should Have |
| T6 | Must support RAG pipeline security (vector store access control, data poisoning detection) | Should Have |
| T7 | Must provide automated remediation via Ansible playbooks for identified AI vulnerabilities | Must Have |
| T8 | Must support Model-as-a-Service with multi-tenant quotas and chargeback | Should Have |
| T9 | Must include an inference gateway with authentication, rate limiting, and routing | Must Have |
| T10 | Must provide SLSA Level 3 software supply chain attestation for all deployed components | Must Have |

---

## 5. Evaluation Criteria

Proposals will be evaluated on the following weighted criteria:

| Criteria | Weight |
|----------|--------|
| Technical capability and platform fit | 35% |
| AI security depth (guardrails, red teaming, supply chain) | 25% |
| Financial services domain expertise and compliance alignment | 20% |
| Pricing and total cost of ownership | 10% |
| Implementation timeline and support model | 10% |

---

## 6. Response Requirements

### 6.1 Proposal Format

Suppliers must respond to each section using the following format:
- **Executive Summary** — 2 pages maximum
- **Technical Response** — Address each requirement in Section 4
- **Security Architecture** — Detailed design for guardrails, red teaming, and vulnerability management
- **Compliance Approach** — How the solution addresses SEC, FINRA, PCI DSS, SOC 2, and EU AI Act
- **Case Studies** — Minimum 2 financial services references with published metrics
- **Pricing** — Broken down by service component, year 1 and years 2-3
- **Team** — Key personnel with relevant certifications and clearances

### 6.2 Mandatory Responses

The supplier must explicitly address:

1. How does your platform handle zero-day vulnerabilities in AI model serving infrastructure?
2. What is your approach to securing RAG pipelines against data poisoning and prompt injection?
3. How do you ensure model governance compliance across disconnected / air-gapped deployments?
4. What SLA do you commit to for critical vulnerability remediation (CVSS >= 9.0)?
5. How does your solution integrate with existing Red Hat ecosystem components (OpenShift, RHACS, Ansible, ACM)?

---

## 7. Commercial

Provide subscription SKUs, professional services rate card, and GPU add-on pricing.

**Note:** All pricing must remain valid for 180 days from submission date.

---

## 8. Timeline

| Event | Date |
|-------|------|
| RFP Issued | 2026-09-01 |
| Intent to Respond | 2026-09-08 |
| Supplier Questions Due | 2026-09-15 |
| Response to Questions | 2026-09-22 |
| Final Proposal Due | 2026-10-31 |
| Supplier Presentations | 2026-11-10 — 2026-11-14 |
| Selection Notification | 2026-12-01 |

---

**Contact:**  
Sarah Chen, VP Strategic Sourcing  
schen@meridiancapital.example.com  

James Rodriguez, CISO Office  
jrodriguez@meridiancapital.example.com
