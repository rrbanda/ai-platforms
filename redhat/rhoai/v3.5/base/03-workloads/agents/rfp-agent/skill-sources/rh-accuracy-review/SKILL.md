# Accuracy Review

> Claim-by-claim review of a draft RFI matrix or RFP section against retrieved knowledge. Load after drafting and before delivery.

## When to Use

- After `rh-rfp-drafting` (RFI matrix or narrative)
- User says "review accuracy", "verify claims", "fact check", "microscopic review"
- `rh-rfp-review` Step 1

## Dependencies

Load `rh-product-naming`. Retrieve with `rh-knowledge-retrieval` for every factual claim unless the user already attached source text.

## Ground-truth sources

1. Passages returned by `rh-knowledge-retrieval` (cite `document_id`)
2. Explicit files the user pasted
3. Do **not** treat the model's prior chat prose as a source

If retrieval returns nothing, verdict is **UNVERIFIABLE**, not ACCURATE.

## Workflow

### Step 1: Inputs

Draft = the matrix or proposal in this chat. Sources = retrieval hits + user files.

### Step 2: Claim table

For every factual claim:

| Claim | Source (`document_id`) | Verdict |
|-------|------------------------|---------|
| exact text | filename or — | verdict |

Verdicts: **ACCURATE**, **INACCURATE** (give correction), **NEEDS NUANCE**, **UNVERIFIABLE** (hallucination risk), **OUTDATED**.

### Step 3: Hard fails

Mark INACCURATE or UNVERIFIABLE immediately if:

- `[GROUNDED]` with citation `none` or missing filename
- Praxis recommended as the product name (must be **Red Hat AI gateway**)
- Kagenti as current
- vLLM listed as a Red Hat product
- Invented GPU-hour price, SKU discount, or 99.999% serving SLA
- Named-customer metrics not in corpus
- DataScienceCluster / workbenches / llm-d / AutoRAG claims that retrieval did not return

### Step 4: Naming

Run `rh-product-naming` on the whole draft.

### Step 5: Summary

```markdown
## Review Summary
- Total claims: N
- Accurate: N
- Inaccurate: N
- Needs nuance: N
- Unverifiable: N
- Naming issues: N
```

Then pause: "Proceed to delivery?"
