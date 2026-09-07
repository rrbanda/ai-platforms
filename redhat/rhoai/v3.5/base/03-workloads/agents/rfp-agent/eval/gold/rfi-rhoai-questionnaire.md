# Gold RFI — OpenShift AI platform questionnaire (internal mock)

**Document job:** RFI / compliance questionnaire  
**Customer (fictional):** Northwind Financial  
**Title:** Request for Information — Enterprise ML/AI Platform on Kubernetes  
**Deadline:** 2026-09-30  
**Format:** complete the matrix. Yes / Partial / No + short evidence. No narrative proposal.

This is a **mock** built from typical OpenShift AI RFI sections (model serving, RAG, guardrails, disconnected, GPU, support). It is not a real customer questionnaire.

| ID | Category | Question | Response type |
|----|----------|----------|---------------|
| Q1 | Platform | Does the solution provide a Kubernetes-native data science platform with a web dashboard, workbenches, and pipeline orchestration? | Yes/Partial/No + describe |
| Q2 | Platform | Can platform components be enabled or disabled via a DataScienceCluster (or equivalent operator) rather than unmanaged Helm-only installs? | Yes/No + describe |
| Q3 | Serving | Can large language models be served with vLLM on NVIDIA and AMD accelerators? | Yes/Partial/No |
| Q4 | Serving | Is distributed inference (llm-d or equivalent) available for production GenAI? | Yes/Partial/No |
| Q5 | Serving | Does the platform support Model-as-a-Service with quotas and chargeback? | Yes/Partial/No |
| Q6 | RAG | Can the platform connect enterprise documents to models via RAG, including automated RAG optimization? | Yes/Partial/No + describe |
| Q7 | Training | Does the platform support distributed training and parameter-efficient fine-tuning (LoRA / QLoRA)? | Yes/Partial/No |
| Q8 | Training | Is InstructLab (or equivalent) available for model customization on this platform? | Yes/Partial/No |
| Q9 | Registry | Is there a model catalog and a model registry with experiment tracking (MLflow or equivalent)? | Yes/Partial/No |
| Q10 | Guardrails | Are runtime guardrails (TrustyAI / NeMo Guardrails) and pre-production red teaming (Garak) available? State GA vs preview. | Yes/Partial/No + status |
| Q11 | Gateway | Is there an inference gateway for auth, rate limits, and routing? Use the customer-facing product name. | Yes/Partial/No + name |
| Q12 | Disconnected | Can OpenShift AI run air-gapped with mirrored images and an offline model catalog? | Yes/Partial/No |
| Q13 | GPU | Can GPUs be pooled and queued (Kueue or equivalent) as a shared utility? | Yes/Partial/No |
| Q14 | Security | How does the vendor manage vulnerabilities (not CVSS-only) and supply chain for container images? | Describe |
| Q15 | Lifecycle | Describe install, upgrade, and backup of the AI platform operators. | Describe |
| Q16 | Support | What production support tiers and SLAs apply? | Describe |
| Q17 | Commercial | Provide list price per GPU-hour and SKU discount schedule for OpenShift AI. | Table |
| Q18 | Evidence | Name three production OpenShift AI customers in banking with published GPU utilization metrics we may cite. | List |
| Q19 | Isolation | If we run coding agents on the platform, how is kernel-escape isolation provided? | Describe |
| Q20 | Naming | Confirm the customer-facing name of the former “Praxis” component. | Name |
