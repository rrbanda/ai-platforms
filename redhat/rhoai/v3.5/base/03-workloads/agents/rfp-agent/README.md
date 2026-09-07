# RFP Response Agent

An AI agent that reads RFP documents, retrieves Red Hat product knowledge, and drafts grounded response sections. Built on the AgentHive platform.

## What it does

| Capability | Description |
|---|---|
| Document intake | Extracts requirements, deadlines, and evaluation criteria from DOCX/PDF |
| Requirement mapping | Maps each requirement to the correct Red Hat product with canonical naming |
| Knowledge retrieval | RAG search of a curated corpus (33 documents across 10 categories) |
| Smart routing | Product questions go to RAG, competitor/industry questions go to web search, pricing is flagged for humans |
| Draft generation | Response sections with real customer evidence, compliance citations, and correct product names |
| Accuracy review | Checks naming compliance, factual grounding, and completeness before delivery |

## Skills

| Skill | Purpose |
|---|---|
| `rh-rfp-intake` | Ingest documents, classify RFI vs RFP, extract timelines |
| `rh-rfp-analysis` | Extract requirements or questionnaire rows |
| `rh-rfp-strategy` | Gap analysis; RFI coverage line per row |
| `rh-rfp-drafting` | Narrative sections or filled RFI matrix |
| `rh-rfp-review` | Completeness and delivery checklist |
| `rh-accuracy-review` | Claim-by-claim check against retrieval |
| `rh-knowledge-retrieval` | RAG search of the curated knowledge corpus |
| `rh-product-naming` | Enforce canonical Red Hat product names |

## Knowledge corpus

33 documents across 10 categories in [`corpus/`](corpus/) (count excludes README). Job spec: [platform/docs/09-rfp-agent-rhoai.md](../../platform/docs/09-rfp-agent-rhoai.md).

| Category | Examples |
|---|---|
| Security | Vulnerability management, AI safety, red teaming |
| Platform | OpenShift AI, ACS, Ansible, Trusted Software Supply Chain |
| Governance | Compliance certifications, responsible AI |
| Product Reference | Naming guide, maturity matrix, STIG/CIS benchmarks |
| Customer Evidence | Financial services, healthcare, telecom, government |
| RFP Examples | Questionnaire response pattern |

## Evaluation

Do **not** treat the following as a live gate. They were a one-off RAGAS snapshot and are **not** reproduced by a Job today.

| Metric | Historical snapshot |
|---|---|
| Faithfulness | 86% |
| Correctness | 64% |

The runnable Job is `rfp-agent-rag-eval` in namespace `rfp-agent-eval`. It clones `main`, evaluates [`eval/gold/benchmark_rhoai.json`](eval/gold/benchmark_rhoai.json) (OpenShift AI questions, naming traps, abstain-correctly), and logs to MLflow experiment `rfp-agent-rag-evaluation`. Thresholds are set after the first honest run.
