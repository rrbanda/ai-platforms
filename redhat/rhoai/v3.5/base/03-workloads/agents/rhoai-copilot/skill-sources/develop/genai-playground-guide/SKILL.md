---
name: genai-playground-guide
description: "Guide users through interactive model experimentation in the GenAI Playground — model selection, parameter tuning, guardrails testing, and response comparison."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, GenAI Playground, Experimentation, Parameters, Guardrails, Model Comparison, Technology Preview]
---

# Interactive Model Experimentation with GenAI Playground

Guide users through the GenAI Playground for interactive experimentation with deployed models — selecting models, tuning generation parameters, testing guardrail behaviors, and comparing responses across models for quality assessment.

> **⚠️ TECHNOLOGY PREVIEW:** The GenAI Playground is a Technology Preview feature in Red Hat OpenShift AI. Technology Preview features are not supported with Red Hat production service level agreements (SLAs), might not be functionally complete, and are not recommended for production use. The Playground interface and capabilities may change between releases.

## Trigger Conditions

- "How do I use the GenAI Playground?"
- "I want to test my model interactively"
- "Compare responses between two models"
- "Tune the temperature for my model"
- "Test guardrails in the Playground"
- "Open the model playground"
- "Experiment with different system prompts"
- "How do I adjust model parameters?"
- "Compare model quality for my use case"
- "Test my deployed model before going to production"

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| `mcp_rhoai` | `list_inference_services` | Find deployed models available in the Playground |
| `mcp_rhoai` | `get_inference_service` | Get model endpoint details and status |
| `mcp_rhoai` | `list_serving_runtimes` | Identify which runtimes support Playground features |
| `mcp_rhoai` | `get_model_endpoint` | Retrieve endpoint URL for direct API access |

## Procedure

### Phase 1: Access and Model Selection

1. Call `mcp_rhoai.list_inference_services` to identify available models:
   - Filter for models in `Ready` state
   - Note which models support chat/completions (required for Playground)
   - Identify model types: instruction-tuned, chat, base, code

2. Call `mcp_rhoai.list_serving_runtimes` to determine Playground compatibility:
   - vLLM serving runtime: full Playground support
   - TGIS: basic Playground support
   - Custom runtimes: may have limited parameter support

3. Guide the user to access the Playground:
   ```
   RHOAI Dashboard → GenAI Playground
   ```
   - The Playground is accessible from the RHOAI dashboard left navigation
   - Users need at least `view` access to the namespace containing the model

4. Help the user select model(s) for experimentation:
   - Single model mode: test one model with parameter variations
   - Comparison mode: test same prompt across 2-3 models side by side

### Phase 2: Parameter Configuration

5. Guide parameter tuning based on the use case:

   | Parameter | Range | Use Case Guidance |
   |-----------|-------|-------------------|
   | `temperature` | 0.0–2.0 | Creative tasks: 0.7–1.2; Factual/code: 0.0–0.3 |
   | `top_p` | 0.0–1.0 | Diverse responses: 0.9–1.0; Focused: 0.1–0.5 |
   | `max_tokens` | 1–model max | Short answers: 256; Long-form: 2048–4096 |
   | `top_k` | 1–100 | Lower = more focused; Higher = more diverse |
   | `repetition_penalty` | 1.0–2.0 | Reduce repetition: 1.1–1.3 |
   | `system_prompt` | Free text | Set model persona, instructions, constraints |

6. Recommend parameter combinations for common tasks:

   **Factual Q&A / RAG:**
   ```
   temperature: 0.1
   top_p: 0.9
   max_tokens: 512
   system_prompt: "Answer questions accurately based on the provided context. If unsure, say so."
   ```

   **Creative Writing:**
   ```
   temperature: 0.9
   top_p: 0.95
   max_tokens: 2048
   system_prompt: "You are a creative writing assistant. Be imaginative and engaging."
   ```

   **Code Generation:**
   ```
   temperature: 0.0
   top_p: 1.0
   max_tokens: 4096
   system_prompt: "Generate clean, well-documented code. Follow best practices."
   ```

   **Summarization:**
   ```
   temperature: 0.3
   top_p: 0.9
   max_tokens: 1024
   system_prompt: "Provide concise, accurate summaries preserving key information."
   ```

### Phase 3: Guardrails Testing

7. If NeMo Guardrails integration is enabled, guide guardrail testing:

   - Verify guardrails configuration is active on the selected model:
     ```bash
     oc get inferenceservice <model> -n <namespace> \
       -o jsonpath='{.metadata.annotations.guardrails\.opendatahub\.io/enabled}'
     ```

   - Test input guardrails (content filtering):
     - Send prompts that should be blocked (harmful content requests)
     - Verify the guardrail intercepts and returns appropriate response
     - Confirm legitimate prompts pass through unaffected

   - Test output guardrails (response filtering):
     - Use prompts that might elicit problematic responses
     - Verify output filtering catches inappropriate content
     - Check that guardrail messages are user-friendly

   - Test topic guardrails (off-topic detection):
     - Send off-topic queries outside the model's intended domain
     - Verify the model redirects to its intended purpose
     - Confirm on-topic queries work normally

8. Document guardrail behavior for the user:
   - Which categories are blocked (violence, PII, profanity, etc.)
   - Response latency impact from guardrail evaluation
   - False positive rate for edge-case prompts

### Phase 4: Model Comparison

9. Set up side-by-side comparison (if user wants to compare models):
   - Select 2-3 models with the same prompt
   - Use identical parameters across models for fair comparison
   - Prepare a set of representative test queries covering:
     - Typical use case queries
     - Edge cases and ambiguous inputs
     - Domain-specific terminology
     - Multi-turn conversation capability

10. Run comparison queries and document results:
    - Response quality (accuracy, completeness, relevance)
    - Response latency (time to first token, total generation time)
    - Token usage (prompt tokens, completion tokens)
    - Format adherence (follows instructions, consistent formatting)
    - Safety behavior (handles sensitive topics appropriately)

11. Provide comparison summary with recommendation:
    - Best overall model for the use case
    - Trade-offs between quality, speed, and cost
    - Parameter adjustments that improve weaker models

### Phase 5: Export and Next Steps

12. Help the user export their findings:
    - Optimal parameter configuration for their use case
    - System prompt that produced best results
    - API call examples using the configured parameters:
      ```bash
      MODEL_URL=$(oc get inferenceservice <model> -n <namespace> \
        -o jsonpath='{.status.url}')

      curl -X POST "${MODEL_URL}/v1/chat/completions" \
        -H "Authorization: Bearer ${API_KEY}" \
        -H "Content-Type: application/json" \
        -d '{
          "model": "<model-name>",
          "messages": [
            {"role": "system", "content": "<optimized-system-prompt>"},
            {"role": "user", "content": "<user-message>"}
          ],
          "temperature": <optimal-temp>,
          "top_p": <optimal-top-p>,
          "max_tokens": <optimal-max-tokens>
        }'
      ```

13. Recommend production deployment path:
    - If guardrails passed → ready for production serving
    - If comparison completed → recommend winning model for deployment
    - Link to deployment skills (`maas-deploy-model`, `model-promotion-workflow`)

## Output Format

```
# GenAI Playground Experimentation Report

## ⚠️ Technology Preview Notice
The GenAI Playground is a Technology Preview feature. Interface and capabilities may change between releases.

## Model(s) Tested
| Model | Runtime | Namespace | Status |
|-------|---------|-----------|--------|
| {model-1} | {vLLM/TGIS} | {ns} | Ready |
| {model-2} | {vLLM/TGIS} | {ns} | Ready |

## Optimal Configuration
- **Model**: {recommended-model}
- **System Prompt**: "{optimized-prompt}"
- **Parameters**:
  - temperature: {value}
  - top_p: {value}
  - max_tokens: {value}
  - top_k: {value} (if applicable)

## Parameter Tuning Results
| Parameter Set | Quality | Latency | Notes |
|---------------|---------|---------|-------|
| {set-1-desc} | {rating}/5 | {ms} | {observation} |
| {set-2-desc} | {rating}/5 | {ms} | {observation} |
| {set-3-desc} | {rating}/5 | {ms} | {observation} |

## Guardrails Testing (if applicable)
| Test Category | Input Blocked | Output Filtered | Latency Impact |
|---------------|---------------|-----------------|----------------|
| Harmful content | ✓ | ✓ | +{ms}ms |
| PII detection | ✓ | ✓ | +{ms}ms |
| Off-topic | ✓ | N/A | +{ms}ms |
| Legitimate prompts | Pass-through | Pass-through | +{ms}ms |

## Model Comparison (if applicable)
| Criteria | {Model-1} | {Model-2} | Winner |
|----------|-----------|-----------|--------|
| Quality | {score}/5 | {score}/5 | {model} |
| Latency | {ms}ms | {ms}ms | {model} |
| Instruction Following | {score}/5 | {score}/5 | {model} |
| Safety | {score}/5 | {score}/5 | {model} |
| **Overall** | | | **{model}** |

## API Integration Example
```bash
curl -X POST "{model-url}/v1/chat/completions" ...
```

## Next Steps
- {Deploy winning model configuration}
- {Configure guardrails for production}
- {Set up monitoring for response quality}
```

## Safety Constraints

- Do not encourage testing with actually harmful prompts — use synthetic/benign test cases that trigger guardrails without containing genuinely dangerous content
- Remind users that Playground conversations may be logged — do not enter sensitive data (credentials, PII, trade secrets)
- Do not share model API keys or endpoints outside the user's authorized namespace
- Warn that parameter extremes (temperature > 1.5, top_k = 1) may produce unreliable or degenerate outputs
- Do not recommend disabling guardrails for production deployments, even if they increase latency
- Remind users that Playground results are indicative, not guaranteed — production behavior depends on actual traffic patterns
- Technology Preview: warn that Playground features may change or be removed in future releases

## Disconnected Environment Notes

- **Dashboard access**: The GenAI Playground is part of the RHOAI dashboard, served from within the cluster — no external connectivity needed for the UI itself
- **Model inference**: All model calls are routed to internal inference endpoints — fully functional in disconnected mode
- **Guardrails**: NeMo Guardrails models must be deployed locally; external guardrail APIs are not reachable
- **No external model comparison**: Cannot compare against external API models (OpenAI, Anthropic) — only locally deployed models are available
- **Documentation links**: In-Playground help links to Red Hat documentation will not load — provide guidance directly through this skill instead
