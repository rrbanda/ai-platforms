# Gold dry-run results

Ran 2026-08-24 against live `rfp-agent` Hermes API (`:8642`, model `rfp-agent`) from inside the sandbox pod. **Open WebUI was not used** (no browser tools in this session). Same OpenAI chat-completions path Open WebUI uses.

Soul/skills on the cluster were **pre-change** (no RFI mode, no `rh-accuracy-review`). New corpus files are in git only; they are **not** in the AutoRAG winner until ingest **and** a vector-io index. See [retrieval-truth.md](retrieval-truth.md).

## RFI package (`rfi-rhoai-questionnaire.md`)

Prompt: classify as RFI; fill 20-row matrix; do not invent prices. Runtime ~20s. Completions 686 tokens.

| ID | Key | Agent | Score |
|----|-----|-------|-------|
| Q1 | SCAFFOLD | Yes `[GROUNDED]` citation none | Overconfident, no cite |
| Q2 | HUMAN (DSC absent in live store) | Yes DSC `[GROUNDED]` none | **Hallucinated** |
| Q3 | AUTO vLLM NVIDIA+AMD | Partial; AMD as Tech Preview | Inaccurate vs corpus |
| Q4 | AUTO llm-d | No; llm-d “not included” | **Hallucinated / wrong** |
| Q5 | AUTO MaaS | Yes; generic K8s quotas | Weak / no cite |
| Q6 | AUTO AutoRAG | Partial; AutoRAG not GA | Status-ish; no cite |
| Q7 | SCAFFOLD LoRA | Yes `[GROUNDED]` none | No cite |
| Q8 | SCAFFOLD InstructLab (`red-hat-responsible-ai.md`) | Yes `[GROUNDED]` none | Exists in corpus; still no cite |
| Q9 | SCAFFOLD catalog/registry | Yes | No cite |
| Q10 | AUTO Garak TP | Partial; “Garak not integrated” | Inaccurate |
| Q11 | AUTO Red Hat AI gateway | “Model Serving” | **Naming fail** |
| Q12 | SCAFFOLD disconnected | Yes | No cite |
| Q13 | SCAFFOLD Kueue | Yes | No cite |
| Q14 | AUTO vuln/TSSC | Yes; “underlying OpenShift” | Vague |
| Q15 | HUMAN lifecycle | Yes `[GROUNDED]` OLM | **Hallucinated** |
| Q16 | SCAFFOLD support | HUMAN | Acceptable |
| Q17 | HUMAN price | HUMAN | **Pass** |
| Q18 | HUMAN named metrics | HUMAN | **Pass** |
| Q19 | AUTO Sandboxed Containers | “standard OpenShift containers” | Inaccurate |
| Q20 | AUTO Red Hat AI gateway | “Model Serving” | **Naming fail** |

**Totals (20 rows):** grounded-with-filename **0/20**; correct HUMAN abstain **2/2** (Q17, Q18); clear hallucinations **Q2, Q4, Q15**; naming fails **Q11, Q20**.

Every `[GROUNDED]` row used citation `none`. That is the highest-leverage skill bug (now called out in soul + `rh-accuracy-review`).

## RFP package (`rfp-rhoai-narrative.md`)

Same API, coverage-matrix-only prompt. **Timed out at 240s** (Hermes full agent loop). No narrative matrix captured. Treat RFI as the scored dry-run. Re-run in Open WebUI after soul remount; expect slow first token.

## Sequenced after this dry-run (in git, not live until push + Argo + pod delete)

- RFI vs RFP in soul, intake, analysis, strategy, drafting
- `rh-accuracy-review` skill wired (parity OK)
- Corpus fills: `openshift-ai-components.md`, `openshift-ai-disconnected.md`, `rfi-questionnaire-response-pattern.md`
- Eval Job `rfp-agent-rag-eval` on `benchmark_rhoai.json`
- Retrieval pin **kept** on AutoRAG winner (named store 404s on vector-io)
- README 86%/64% demoted; not a gate

After `main` is pushed: wait for Argo, delete pod `rfp-agent` if PostSync Job does not remount, **new Open WebUI chat**, attach the gold RFI, confirm citations are filenames and Praxis → Red Hat AI gateway.
