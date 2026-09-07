# Gold fixtures — OpenShift AI RFP / RFI

Internal mocks used to **measure** rfp-agent. They are not customer packages and must not be ingested into `rfp_knowledge_v1` (this directory is outside `agents/rfp-agent/corpus/`).

| File | Role |
|------|------|
| [taxonomy.yaml](taxonomy.yaml) | OpenShift AI buyer-question spine |
| [rfi-rhoai-questionnaire.md](rfi-rhoai-questionnaire.md) | Gold RFI (matrix) |
| [rfp-rhoai-narrative.md](rfp-rhoai-narrative.md) | Gold RFP (narrative) |
| [rfi-answer-key.json](rfi-answer-key.json) | Human key: AUTO / SCAFFOLD / HUMAN + expected docs |
| [rfp-answer-key.json](rfp-answer-key.json) | Same for the narrative RFP |
| [benchmark_rhoai.json](benchmark_rhoai.json) | Eval Job input (taxonomy + traps + naming) |
| [coverage-matrix.md](coverage-matrix.md) | Corpus vs taxonomy scores |
| [retrieval-truth.md](retrieval-truth.md) | Named store vs AutoRAG winner |
| [dry-run-results.md](dry-run-results.md) | Open WebUI / API dry-run score |

If a real sanitized customer package is added later, keep the same answer-key schema and point the Job `BENCHMARK_PATH` here.
