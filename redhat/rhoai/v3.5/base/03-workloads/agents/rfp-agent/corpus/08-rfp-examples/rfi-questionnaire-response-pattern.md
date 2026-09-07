---
title: RFI questionnaire response pattern
date: 2026-08-24
source: Internal rfp-agent job spec (platform/docs/09-rfp-agent-rhoai.md)
product_area: RFP process
---

# RFI questionnaire response pattern

This is a **structure example**, not a filled customer questionnaire and not evidence for product claims.

When intake classifies the package as **RFI / questionnaire** (Excel, Yes/No/Partial matrices):

1. Do **not** switch to the services or technology narrative templates.
2. Emit one row per inbound question.
3. Every row has: ID, Answer (Yes / Partial / No / HUMAN), Citation (`document_id` filename), one-line evidence.
4. `[GROUNDED]` only when a retrieval `document_id` is cited. Never write `[GROUNDED]` with citation `none`.
5. Pricing, legal, unapproved metrics, missing lifecycle steps → **HUMAN**.
6. Product names from `product-naming-canonical.md` only. Former “Praxis” → **Red Hat AI gateway**.

## Row template

| ID | Answer | Citation | Evidence |
|----|--------|----------|----------|
| Qn | Yes / Partial / No / HUMAN | `filename.md` or — | Quote or paraphrase from that file |

## After the matrix

Stop. Ask “Proceed to review?” Do not auto-generate a 40-page proposal unless the user confirms a hybrid RFP is also in the package.
