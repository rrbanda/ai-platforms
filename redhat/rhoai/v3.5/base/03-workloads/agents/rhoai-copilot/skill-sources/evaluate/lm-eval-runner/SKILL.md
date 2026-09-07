---
name: lm-eval-runner
description: "Run LM-Eval benchmarks via EvalHub to evaluate LLM performance on standardized tasks using TrustyAI's LMEvalJob CRD."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Evaluate, LM-Eval, Benchmark, TrustyAI, EvalHub, MMLU, LLM]
---

# LM-Eval Benchmark Runner

Run standardized LLM evaluation benchmarks through EvalHub on Red Hat OpenShift AI using the LMEvalJob CRD managed by the TrustyAI operator. Supports 167+ benchmarks from lm_evaluation_harness, 12 from garak (safety), and 4 from guidellm (latency/throughput), with configurable pass/fail thresholds and reusable benchmark collections.

## Trigger Conditions

- "Evaluate my model with MMLU"
- "Run LM-Eval benchmarks on my deployed model"
- "Benchmark model accuracy on GSM8K"
- "Compare model performance across tasks"
- "Set up an evaluation job for my InferenceService"
- "Run HellaSwag and ARC Challenge on the model"
- "Create a benchmark suite for model validation"
- "How do I evaluate LLM quality on RHOAI?"
- User wants to measure model quality before or after deployment
- Model promotion gate requires evaluation scores

## Required MCP Tools

### mcp_rhoai
- `list_inference_services` — discover deployed models available for evaluation
- `get_inference_service` — retrieve model endpoint URL and serving details
- `cluster_summary` — check TrustyAI operator status and namespace readiness
- `explore_cluster` — find LMEvalJob CRDs and existing evaluation results

### mcp_openshift
- `pods_list` — monitor evaluator pod lifecycle and status
- `pods_log` — retrieve evaluation logs and partial results
- `events_list` — detect scheduling failures or resource issues

## Procedure

### Phase 1: Validate Platform Readiness

1. Verify TrustyAI operator is enabled:
   ```bash
   oc get dsc default-dsc -o jsonpath='{.spec.components.trustyai.managementState}'
   # Must be: Managed
   ```

2. Confirm the LMEvalJob CRD exists:
   ```bash
   oc get crd lmevaljobs.trustyai.opendatahub.io
   ```

3. Call `mcp_rhoai.cluster_summary` to verify TrustyAI pods are running.

### Phase 2: Identify Target Model

4. Call `mcp_rhoai.list_inference_services` to find the model to evaluate.

5. Call `mcp_rhoai.get_inference_service` to retrieve the model endpoint:
   - Internal URL (preferred for evaluation): `http://<service>.<namespace>.svc.cluster.local/v1`
   - Model name as reported by the serving runtime

6. Verify the model is ready and serving:
   ```bash
   oc get inferenceservice <name> -n <namespace> -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
   # Must be: True
   ```

### Phase 3: Select Benchmarks

7. Guide the user through benchmark selection based on evaluation goals:

   | Goal | Recommended Benchmarks | Provider |
   |------|----------------------|----------|
   | General knowledge | MMLU (57 subjects) | lm_evaluation_harness |
   | Reasoning | ARC Challenge, HellaSwag, WinoGrande | lm_evaluation_harness |
   | Math/logic | GSM8K | lm_evaluation_harness |
   | Truthfulness | TruthfulQA | lm_evaluation_harness |
   | Safety/adversarial | garak probes | garak |
   | Latency/throughput | guidellm scenarios | guidellm |
   | Code generation | HumanEval, MBPP | lm_evaluation_harness |

8. For reusable evaluation suites, use EvalHub Collections:
   ```yaml
   apiVersion: trustyai.opendatahub.io/v1alpha1
   kind: EvalCollection
   metadata:
     name: standard-llm-suite
     namespace: <namespace>
   spec:
     benchmarks:
       - name: mmlu
         provider: lm_evaluation_harness
         args:
           num_fewshot: 5
       - name: hellaswag
         provider: lm_evaluation_harness
         args:
           num_fewshot: 10
       - name: gsm8k
         provider: lm_evaluation_harness
         args:
           num_fewshot: 5
       - name: arc_challenge
         provider: lm_evaluation_harness
         args:
           num_fewshot: 25
   ```

### Phase 4: Create LMEvalJob

9. Generate the LMEvalJob manifest:
   ```yaml
   apiVersion: trustyai.opendatahub.io/v1alpha1
   kind: LMEvalJob
   metadata:
     name: <eval-job-name>
     namespace: <namespace>
   spec:
     model: local-completions
     modelArgs:
       - name: model
         value: <model-name-from-serving>
       - name: base_url
         value: "http://<inference-service>.<namespace>.svc.cluster.local/v1"
       - name: tokenized_requests
         value: "False"
       - name: num_concurrent
         value: "4"
     taskList:
       taskNames:
         - <benchmark-1>
         - <benchmark-2>
     numFewShot: <n>
     batchSize: "auto"
     passCriteria:
       - taskName: <benchmark-1>
         metric: acc
         operator: ">="
         threshold: <value>
         result: pass
       - taskName: <benchmark-1>
         metric: acc
         operator: "<"
         threshold: <value>
         result: fail
     pod:
       resources:
         requests:
           cpu: "2"
           memory: "4Gi"
         limits:
           cpu: "4"
           memory: "8Gi"
   ```

10. For chat/instruct models, add `apply_chat_template` argument:
    ```yaml
    modelArgs:
      - name: apply_chat_template
        value: "True"
      - name: tokenizer_backend
        value: "huggingface"
    ```

11. Configure pass criteria thresholds (example baselines for common benchmarks):

    | Benchmark | Metric | 7B Baseline | 13B Baseline | 70B Baseline |
    |-----------|--------|-------------|--------------|--------------|
    | MMLU | acc | 0.45 | 0.55 | 0.70 |
    | HellaSwag | acc_norm | 0.75 | 0.80 | 0.85 |
    | GSM8K | exact_match | 0.30 | 0.45 | 0.65 |
    | ARC Challenge | acc_norm | 0.50 | 0.55 | 0.65 |
    | WinoGrande | acc | 0.70 | 0.75 | 0.80 |
    | TruthfulQA | mc2 | 0.40 | 0.45 | 0.50 |

### Phase 5: Submit and Monitor

12. Apply the LMEvalJob:
    ```bash
    oc apply -f <eval-job>.yaml
    ```

13. Monitor evaluation progress:
    ```bash
    oc get lmevaljob <name> -n <namespace> -o jsonpath='{.status.state}'
    # States: Pending → Running → Complete | Failed
    ```

14. Watch evaluator pod logs for progress:
    ```bash
    oc logs -f job/<eval-job-name> -n <namespace>
    ```
    Call `mcp_openshift.pods_log` for programmatic access.

15. If evaluation fails, check events:
    - Call `mcp_openshift.events_list` for the namespace
    - Common failures: model endpoint unreachable, OOM on evaluator pod, dataset download timeout

### Phase 6: Retrieve and Interpret Results

16. Get results from the LMEvalJob status:
    ```bash
    oc get lmevaljob <name> -n <namespace> -o jsonpath='{.status.results}'
    ```

17. Check pass/fail outcome:
    ```bash
    oc get lmevaljob <name> -n <namespace> -o jsonpath='{.status.passCriteriaResult}'
    # Values: pass | fail | partially_failed
    ```

18. Access the EvalHub Dashboard (Technology Preview) for visual result exploration:
    ```bash
    oc get route evalhub-dashboard -n <trustyai-namespace> -o jsonpath='{.spec.host}'
    ```

## Output Format

```
# Evaluation Results: {model_name}

## Job Summary
- LMEvalJob: {job_name}
- Model: {model_name} @ {endpoint}
- Duration: {elapsed_time}
- Status: {Complete|Failed}
- Pass Criteria: {pass|fail|partially_failed}

## Benchmark Scores
| Benchmark | Metric | Score | Threshold | Result |
|-----------|--------|-------|-----------|--------|
| {name} | {metric} | {score} | {threshold} | {pass/fail} |
| ... | ... | ... | ... | ... |

## Analysis
- Strengths: {areas where model exceeds thresholds}
- Weaknesses: {areas where model underperforms}
- Recommendation: {proceed to deploy / retrain / investigate}

## Artifacts
- Full results: oc get lmevaljob {name} -n {ns} -o yaml
- Dashboard: https://{dashboard_host}/evaluations/{job_id}
- Logs: oc logs job/{name} -n {ns}
```

## Safety Constraints

- Never modify a running InferenceService during evaluation — results become unreliable
- Do not run large benchmark suites (>10 tasks) without confirming the evaluator pod has sufficient memory (recommend 8Gi+ for large suites)
- Warn the user that evaluation jobs generate significant inference load — avoid running during peak serving periods
- Never expose internal model endpoints externally for evaluation; always use cluster-internal URLs
- Do not override pass criteria to force a passing result — report honestly
- If a model fails pass criteria, clearly state it and recommend next steps rather than proceeding to deployment

## Disconnected Environment Notes

- LMEvalJob pods download benchmark datasets from HuggingFace Hub by default; in disconnected environments, pre-cache datasets to a PVC:
  ```yaml
  spec:
    pod:
      volumes:
        - name: eval-data
          persistentVolumeClaim:
            claimName: lm-eval-datasets
      volumeMounts:
        - name: eval-data
          mountPath: /root/.cache/huggingface
      env:
        - name: HF_HOME
          value: /root/.cache/huggingface
        - name: HF_DATASETS_OFFLINE
          value: "1"
  ```
- Mirror evaluator images from `quay.io/trustyai` to the internal registry
- The `model` connection uses cluster-internal URLs — no external network needed for inference calls
- garak probes that fetch adversarial datasets externally will fail; use only locally-available probe sets
- EvalHub Dashboard is served internally and does not require external connectivity
