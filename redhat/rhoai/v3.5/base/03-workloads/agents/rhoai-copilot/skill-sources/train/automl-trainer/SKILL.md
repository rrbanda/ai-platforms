---
name: automl-trainer
description: "Configure and run AutoML to automatically train, compare, and select the best ML models — leaderboard comparison, notebook generation, and model registry integration."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, AutoML, Training, Model Selection, Leaderboard, Model Registry, Notebook, Technology Preview]
---

# Automated Model Training with AutoML

Configure and run AutoML to automatically train multiple ML models, compare their performance on a leaderboard, generate notebooks for the best configurations, and register winning models for deployment.

> **⚠️ TECHNOLOGY PREVIEW:** AutoML is a Technology Preview feature in Red Hat OpenShift AI. Technology Preview features are not supported with Red Hat production service level agreements (SLAs), might not be functionally complete, and are not recommended for production use. Model training results and auto-generated configurations may require manual validation before production deployment.

## Trigger Conditions

- "Train a model automatically"
- "Find the best model for my dataset"
- "Run AutoML optimization"
- "Compare model architectures for my task"
- "Which algorithm works best for my data?"
- "Show the AutoML leaderboard"
- "Generate a notebook for the best model"
- "Register the winning model from AutoML"
- "Automate hyperparameter tuning"
- "I have a dataset — help me train the best model"

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| `mcp_rhoai` | `cluster_summary` | Verify RHOAI version and AutoML availability |
| `mcp_rhoai` | `explore_cluster` | Discover existing AutoML runs and configurations |
| `mcp_rhoai` | `list_registered_models` | Check model registry for existing models and versions |
| `mcp_openshift` | `pods_list` | Monitor AutoML training pod status |
| `mcp_openshift` | `events_list` | Diagnose scheduling, GPU, and resource issues |

## Procedure

### Phase 1: Prerequisites Verification

1. Call `mcp_rhoai.cluster_summary` to confirm:
   - RHOAI version ≥ 3.4
   - AutoML component is available
   - Training operator is enabled in DataScienceCluster
   - Sufficient GPU/CPU resources for training workloads

2. Call `mcp_rhoai.explore_cluster` to check for:
   - Existing AutoML runs and their results
   - Configured data connections (S3, PVC)
   - Available hardware profiles for training

3. Call `mcp_rhoai.list_registered_models` to understand:
   - Existing models in the registry (avoid duplicate work)
   - Model naming conventions in use
   - Available model formats and frameworks

### Phase 2: Configure Training Run

4. Gather training parameters from the user:

   | Parameter | Options | Description |
   |-----------|---------|-------------|
   | Task type | `classification`, `regression`, `forecasting`, `nlp`, `vision` | ML task category |
   | Dataset | PVC path / S3 URI / data connection | Training data source |
   | Target column | Column name | Label/target for supervised learning |
   | Time budget | Minutes | Maximum training duration |
   | Metric | `accuracy`, `f1`, `rmse`, `mae`, `auc` | Primary optimization metric |
   | Max models | Integer | Maximum number of model candidates |
   | Frameworks | `sklearn`, `xgboost`, `lightgbm`, `pytorch`, `tensorflow` | Allowed frameworks |

5. Create the AutoML training configuration:
   ```yaml
   apiVersion: automl.opendatahub.io/v1alpha1
   kind: AutoMLRun
   metadata:
     name: automl-<task>-<timestamp>
     namespace: <project-namespace>
   spec:
     task:
       type: classification  # or regression, forecasting, etc.
       metric: f1
       direction: maximize
     dataset:
       source:
         type: pvc  # or s3, data-connection
         pvcName: <dataset-pvc>
         path: /data/train.csv
       target: <target-column>
       validation:
         split: 0.2  # 80/20 train/val split
         strategy: stratified  # or random, time-series
     searchSpace:
       frameworks:
         - sklearn
         - xgboost
         - lightgbm
       models:
         classification:
           - RandomForest
           - GradientBoosting
           - XGBClassifier
           - LGBMClassifier
           - LogisticRegression
           - SVM
       hyperparameters:
         strategy: bayesian  # or grid, random
         maxTrials: 50
     constraints:
       timeBudgetMinutes: 60
       maxModels: 10
       earlyStoppingRounds: 5
       earlyStoppingPatience: 3
     resources:
       perTrial:
         requests:
           cpu: "2"
           memory: "4Gi"
         limits:
           cpu: "4"
           memory: "8Gi"
       gpuPerTrial: 0  # Set > 0 for deep learning tasks
   ```

6. Apply the AutoML run:
   ```bash
   oc apply -f automl-run.yaml
   ```

### Phase 3: Monitor Training

7. Track training progress:
   ```bash
   oc get automlrun <name> -n <namespace> -o jsonpath='{.status}'
   ```
   Status fields:
   - `phase`: Pending → DataValidation → Training → Evaluating → Completed
   - `progress`: percentage complete
   - `currentTrial`: trial number being trained
   - `totalTrials`: total trials planned
   - `bestScore`: best metric value so far
   - `bestModel`: current leading model name

8. Call `mcp_openshift.pods_list` to monitor training pods:
   - Look for pods with label `automl.opendatahub.io/run=<run-name>`
   - Multiple pods may run in parallel (one per trial)

9. Call `mcp_openshift.events_list` if pods are pending or failing:
   - GPU quota exhaustion
   - PVC mount failures
   - OOM kills on memory-intensive models

10. Monitor intermediate leaderboard updates:
    ```bash
    oc get automlrun <name> -n <namespace> \
      -o jsonpath='{.status.leaderboard[0:5]}' | jq .
    ```

### Phase 4: Review Leaderboard

11. Once status is `Completed`, retrieve the full leaderboard:
    ```bash
    oc get automlrun <name> -n <namespace> \
      -o jsonpath='{.status.leaderboard}' | jq .
    ```

12. The leaderboard includes for each model:
    - Model type and framework
    - Hyperparameters used
    - Training duration
    - All metric scores (primary + secondary)
    - Model artifact path

13. Access the AutoML Dashboard UI for interactive exploration:
    ```bash
    DASHBOARD_URL=$(oc get route automl-dashboard -n <namespace> -o jsonpath='{.spec.host}')
    echo "https://${DASHBOARD_URL}/runs/<run-name>"
    ```

### Phase 5: Generate Notebook

14. Generate a notebook for the winning model:
    ```bash
    oc get automlrun <name> -n <namespace> \
      -o jsonpath='{.status.winnerNotebook}' > best-model-notebook.ipynb
    ```

15. The generated notebook includes:
    - Data loading and preprocessing pipeline
    - Feature engineering steps (if applied)
    - Model instantiation with winning hyperparameters
    - Training code with cross-validation
    - Evaluation metrics and visualization
    - Model serialization (ONNX, pickle, or framework-native)

### Phase 6: Register Winning Model

16. Register the winning model in the Model Registry:
    ```bash
    oc get automlrun <name> -n <namespace> \
      -o jsonpath='{.status.winner.artifactPath}'
    ```

17. Create a RegisteredModel if one does not exist:
    ```yaml
    apiVersion: modelregistry.opendatahub.io/v1alpha1
    kind: RegisteredModel
    metadata:
      name: <model-name>
      namespace: <registry-namespace>
    spec:
      description: "AutoML winner: {model-type} trained on {dataset}"
      owner: <user>
    ```

18. Create a ModelVersion referencing the artifact:
    ```yaml
    apiVersion: modelregistry.opendatahub.io/v1alpha1
    kind: ModelVersion
    metadata:
      name: <model-name>-v<version>
      namespace: <registry-namespace>
    spec:
      registeredModelName: <model-name>
      description: "AutoML run {run-name} winner — {metric}={score}"
      artifacts:
        - name: model
          uri: <artifact-path>
          modelFormatName: <format>  # onnx, sklearn, xgboost, etc.
      metadata:
        automl_run: <run-name>
        training_duration: <duration>
        primary_metric: <metric>=<score>
    ```

19. Confirm registration:
    ```bash
    oc get registeredmodel <model-name> -n <registry-namespace>
    oc get modelversion -l registeredmodel=<model-name> -n <registry-namespace>
    ```

## Output Format

```
# AutoML Training Report

## ⚠️ Technology Preview Notice
AutoML is a Technology Preview feature. Results should be validated before production use.

## Run Summary
- Run Name: {run-name}
- Namespace: {namespace}
- Task Type: {classification/regression/etc.}
- Primary Metric: {metric} (direction: {maximize/minimize})
- Duration: {elapsed-time}
- Total Trials: {count}
- Dataset: {source} ({rows} rows, {features} features)

## Leaderboard (Top 5)

| Rank | Model | Framework | {Metric} | Training Time | Parameters |
|------|-------|-----------|----------|---------------|------------|
| 1 🏆 | {type} | {framework} | {score} | {duration} | {key-params} |
| 2    | {type} | {framework} | {score} | {duration} | {key-params} |
| 3    | {type} | {framework} | {score} | {duration} | {key-params} |
| 4    | {type} | {framework} | {score} | {duration} | {key-params} |
| 5    | {type} | {framework} | {score} | {duration} | {key-params} |

## Winner Details
- **Model**: {model-type} ({framework})
- **Hyperparameters**: {key-value pairs}
- **Scores**:
  - {primary-metric}: {score}
  - {secondary-metric-1}: {score}
  - {secondary-metric-2}: {score}
- **Training Duration**: {time}
- **Artifact Path**: {path}

## Model Registration
- Registered Model: {name}
- Version: {version}
- Format: {onnx/sklearn/xgboost/etc.}
- Registry: {namespace}

## Key Insights
1. {Insight about model type dominance}
2. {Insight about hyperparameter sensitivity}
3. {Insight about data characteristics affecting results}

## Generated Artifacts
- Notebook: {path-to-notebook}
- Dashboard: {dashboard-url}
- Model Artifact: {artifact-path}

## Next Steps
- {Deploy model via model serving (link to deploy skills)}
- {Run evaluation benchmarks}
- {Iterate with feature engineering}
```

## Safety Constraints

- Do not train on datasets containing PII without explicit user confirmation that data handling policies are met
- Warn about compute costs — AutoML can consume significant GPU/CPU resources across many trials
- Do not automatically register models to production-facing registries — require explicit user confirmation
- Respect namespace resource quotas — adjust `maxTrials` and `perTrial` resources accordingly
- Do not expose training data or model artifacts outside the configured namespace
- Warn that Technology Preview training infrastructure may not guarantee reproducibility across versions
- Early stopping must be configured to prevent runaway resource consumption
- Validate dataset integrity (no null targets, correct dtypes) before starting an expensive training run

## Disconnected Environment Notes

- **AutoML images**: Mirror the AutoML controller and training worker images:
  ```yaml
  mirror:
    additionalImages:
      - name: registry.redhat.io/rhoai/automl-controller-rhel9:latest
      - name: registry.redhat.io/rhoai/automl-worker-rhel9:latest
  ```
- **Framework dependencies**: Training images include sklearn, xgboost, lightgbm, and PyTorch. No pip installs from external PyPI occur at runtime
- **Dataset access**: Training data must be on PVC or internal S3 (MinIO) — no external data lake connectivity
- **Model Registry**: The model registry is cluster-internal; registration does not require external connectivity
- **Dashboard UI**: The AutoML dashboard is served from within the cluster and works fully offline
- **Notebook generation**: Generated notebooks reference internal endpoints and data sources only
