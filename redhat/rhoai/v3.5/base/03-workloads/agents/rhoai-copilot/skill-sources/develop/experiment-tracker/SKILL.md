---
name: experiment-tracker
description: "MLflow experiment tracking integration — compare training runs, select best model, and track metrics."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Data Scientist, MLflow, Experiments, Metrics, Comparison]
---

# Experiment Tracker

Integrates with MLflow to compare training runs, analyze experiment metrics, select best models, and track model lineage.

## Trigger Phrases

- "Compare my last 3 runs"
- "Show me my experiment results"
- "Which run has the best accuracy?"
- "What metrics did my training produce?"
- "Show experiment history for model X"
- "Find the best model from my experiments"

## Procedure

### Phase 1: Identify Experiment

1. Call `mcp_mlflow_search_experiments` to list available experiments:
   - Show experiment names, IDs, and last activity
   - Help user identify the target experiment
2. If user specifies a model name, search by name pattern
3. Call `mcp_mlflow_get_experiment` for the target experiment:
   - Get experiment metadata and artifact location

### Phase 2: Retrieve Runs

4. Call `mcp_mlflow_list_runs` for the experiment:
   - Get all runs (or filter by status: FINISHED, FAILED, RUNNING)
   - Sort by start_time or a specific metric
5. For each run of interest:
   - Call `mcp_mlflow_describe_run` to get full details:
     - Parameters (hyperparameters used)
     - Metrics (training loss, eval metrics)
     - Tags (model type, hardware used)
     - Artifacts (model checkpoints, configs)

### Phase 3: Comparison Analysis

6. Build comparison table across runs:
   - Identify key metrics for comparison:
     - Training loss (final)
     - Validation loss
     - Accuracy / F1 / BLEU (task-dependent)
     - Training time
     - GPU utilization
   - Identify key parameters that varied between runs:
     - Learning rate
     - Batch size
     - Number of epochs
     - Model architecture variations
     - LoRA rank (if applicable)

7. Determine the "best" run based on:
   - Primary metric (user-specified or inferred from task type)
   - Pareto-optimal: best metric with acceptable training time
   - Stability: consistent performance across validation splits

### Phase 4: Model Selection

8. For the winning run:
   - Identify the model artifact path
   - Check if it's registered in Model Registry:
     - Call `mcp_rhoai_list_registered_models` to check
   - Recommend registration if not yet registered
9. Provide deployment readiness assessment:
   - Model size and format
   - Recommended serving runtime (link to `serving-runtime-advisor` skill)
   - Resource requirements for inference

### Phase 5: Insights and Recommendations

10. Provide analytical insights:
    - Trend analysis: are metrics improving across runs?
    - Hyperparameter sensitivity: which params had most impact?
    - Diminishing returns: is more training unlikely to help?
    - Next experiment suggestions based on patterns

## Output Format

```
# Experiment Report: {experiment_name}

## Summary
- Experiment ID: {id}
- Total runs: {count}
- Successful: {count}
- Best run: {run_id} ({primary_metric}={value})

## Run Comparison

### Metrics
| Run | {metric_1} | {metric_2} | {metric_3} | Duration | Status |
|-----|-----------|-----------|-----------|----------|--------|
| {run_1} | {val} | {val} | {val} | {time} | ✓ |
| {run_2} | {val} | {val} | {val} | {time} | ✓ |
| {run_3} | {val} | {val} | {val} | {time} | ✓ |

### Parameters (varied)
| Run | {param_1} | {param_2} | {param_3} |
|-----|----------|----------|----------|
| {run_1} | {val} | {val} | {val} |
| {run_2} | {val} | {val} | {val} |
| {run_3} | {val} | {val} | {val} |

## Winner: Run {run_id}
- **Why**: {reasoning — best {metric} with acceptable {tradeoff}}
- Model artifact: {path}
- Registered: {yes (version X) / no — recommend registering}

## Insights
1. **{Insight 1}**: {description}
2. **{Insight 2}**: {description}
3. **{Insight 3}**: {description}

## Recommendations
- **Next experiment**: {suggestion based on trend analysis}
- **Deployment**: {runtime recommendation, resource estimate}
- **Registration**: {register model version X in Model Registry}

## Traces (if available)
| Trace | Score | Duration | Tokens |
|-------|-------|----------|--------|
| {trace_id} | {score} | {ms} | {count} |
```

## Domain Knowledge

- MLflow in RHOAI is deployed as a shared tracking server in `redhat-ods-applications`
- Experiments map to Data Science Projects — each project has its own experiment namespace
- Model artifacts are stored in the project's S3 data connection (not MLflow server itself)
- MLflow UI is accessible via the RHOAI Dashboard under "Experiments"
- Traces in MLflow track LLM inference calls (input/output/latency) — useful for eval
- Model Registry in RHOAI is separate from MLflow model logging — explicit registration needed
- Compare at least 3 runs to identify meaningful trends vs noise
- When metrics plateau across runs with different hyperparameters, the model may need more data, not more tuning
