---
name: model-drift-monitor
description: "Configure and interpret TrustyAI model bias and data drift monitoring — set up metrics, thresholds, and alerts for deployed models."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, TrustyAI, Bias, Drift, Monitoring, Fairness, Prometheus]
---

# Model Drift Monitor

Configure and interpret TrustyAI model bias and data drift monitoring for deployed models on RHOAI. Enables continuous fairness assessment and input data distribution tracking through Prometheus metrics and the OpenShift monitoring stack.

## Trigger Conditions

- "Set up bias monitoring for my model"
- "Is my model drifting?"
- "Configure fairness metrics"
- "Check SPD and DIR for my deployment"
- "My model predictions seem less accurate lately"
- "Set up data drift detection"
- "Configure TrustyAI for my InferenceService"
- "What bias metrics are available?"
- "Alert me when model fairness degrades"
- "Show me drift metrics for the last week"

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| mcp_rhoai | list_inference_services | Find deployed models to monitor |
| mcp_rhoai | get_inference_service | Get model deployment details |
| mcp_rhoai | cluster_summary | Check TrustyAI component status |
| mcp_openshift | pods_list | Find TrustyAI operator and service pods |
| mcp_openshift | pods_log | Retrieve TrustyAI service logs |
| mcp_openshift | resources_list | List TrustyAI CRs and monitoring resources |
| mcp_openshift | events_list | TrustyAI reconciliation events |
| mcp_openshift | nodes_top | Resource usage for monitoring workloads |

## Procedure

### Phase 1: TrustyAI Readiness Check

1. Call `mcp_rhoai` → `cluster_summary` to verify:
   - DSC component `trustyai` has `managementState: Managed`
   - TrustyAI operator is running and healthy
2. Call `mcp_openshift` → `pods_list` in namespace `redhat-ods-applications` to find:
   - `trustyai-service-operator-controller-manager` pod — the operator
   - Verify it is Running with Ready condition
3. Call `mcp_openshift` → `resources_list` with kind=`TrustyAIService` to check if TrustyAI is deployed in the model's namespace:
   - Each namespace with monitored models needs a TrustyAIService CR
   - If missing, guide the user to create one

### Phase 2: Model Discovery

4. Call `mcp_rhoai` → `list_inference_services` to enumerate deployed models
5. Call `mcp_rhoai` → `get_inference_service` for the target model to determine:
   - Model name and namespace
   - Serving runtime (vLLM, TGIS, OpenVINO)
   - Input/output schema (needed for drift feature configuration)
   - Current traffic and replica count
6. Call `mcp_openshift` → `pods_list` in the model's namespace to find the TrustyAI service pod:
   - Named `trustyai-service-{hash}`
   - Must be Running and collecting inference data

### Phase 3: Bias Metrics Configuration

7. Configure **Statistical Parity Difference (SPD)** monitoring:
   - SPD measures whether a protected group receives favorable outcomes at the same rate as the reference group
   - Range: [-1, 1], ideal = 0
   - Thresholds: |SPD| > 0.1 indicates potential bias
   ```yaml
   apiVersion: trustyai.opendatahub.io/v1alpha1
   kind: BiasMetric
   metadata:
     name: {model}-spd-{attribute}
     namespace: {namespace}
   spec:
     modelId: {inference_service_name}
     metricName: SPD
     protectedAttribute: {feature_name}
     favorableOutcome: {outcome_value}
     privilegedAttribute: {privileged_value}
     unprivilegedAttribute: {unprivileged_value}
     outcomeName: {prediction_field}
     schedule:
       frequency: "*/5 * * * *"
     thresholds:
       lower: -0.1
       upper: 0.1
   ```

8. Configure **Disparate Impact Ratio (DIR)** monitoring:
   - DIR measures the ratio of favorable outcome rates between unprivileged and privileged groups
   - Range: [0, ∞), ideal = 1.0
   - Thresholds: DIR < 0.8 or DIR > 1.25 indicates potential bias
   ```yaml
   apiVersion: trustyai.opendatahub.io/v1alpha1
   kind: BiasMetric
   metadata:
     name: {model}-dir-{attribute}
     namespace: {namespace}
   spec:
     modelId: {inference_service_name}
     metricName: DIR
     protectedAttribute: {feature_name}
     favorableOutcome: {outcome_value}
     privilegedAttribute: {privileged_value}
     unprivilegedAttribute: {unprivileged_value}
     outcomeName: {prediction_field}
     schedule:
       frequency: "*/5 * * * *"
     thresholds:
       lower: 0.8
       upper: 1.25
   ```

### Phase 4: Data Drift Configuration

9. Configure data drift monitoring to detect input distribution changes:
   - Tracks feature value distributions over time
   - Compares recent inference data against a training-time baseline
   - Uses statistical tests (KS test, PSI) to quantify drift magnitude
   ```yaml
   apiVersion: trustyai.opendatahub.io/v1alpha1
   kind: DriftMetric
   metadata:
     name: {model}-drift-{feature}
     namespace: {namespace}
   spec:
     modelId: {inference_service_name}
     metricName: MeanshiftRatio
     features:
       - name: {feature_name}
         type: {numeric|categorical}
     referenceTag: training
     schedule:
       frequency: "*/15 * * * *"
     thresholds:
       upper: 0.25
   ```

10. Drift metric options:
    | Metric | Use Case | Threshold |
    |--------|----------|-----------|
    | MeanshiftRatio | Numeric feature mean shift | > 0.25 |
    | FourierMMD | Distribution divergence (non-parametric) | > 0.05 |
    | KSTest | Kolmogorov-Smirnov test for distribution change | p < 0.05 |
    | PSI (Population Stability Index) | Categorical feature stability | > 0.2 |

### Phase 5: Prometheus Integration

11. TrustyAI exposes metrics via the OpenShift monitoring stack:
    - Metrics endpoint: `trustyai-service:8080/metrics`
    - Namespace: user workload monitoring must be enabled
    - ServiceMonitor CR auto-created by TrustyAI operator
12. Key Prometheus metrics:
    | Metric | Description | Labels |
    |--------|-------------|--------|
    | `trustyai_spd` | Statistical Parity Difference | model, protected_attribute |
    | `trustyai_dir` | Disparate Impact Ratio | model, protected_attribute |
    | `trustyai_drift_meanshift` | Mean shift ratio | model, feature |
    | `trustyai_drift_mmd` | MMD score | model, feature |
    | `trustyai_data_count` | Inference records collected | model |
13. Verify metrics are scraped:
    - Call `mcp_openshift` → `resources_list` with kind=`ServiceMonitor` in the model namespace
    - Check that `openshift-user-workload-monitoring` Prometheus is scraping the endpoint

### Phase 6: Alerting Configuration

14. Create PrometheusRule for bias alerts:
    ```yaml
    apiVersion: monitoring.coreos.com/v1
    kind: PrometheusRule
    metadata:
      name: trustyai-{model}-alerts
      namespace: {namespace}
    spec:
      groups:
        - name: model-fairness
          rules:
            - alert: ModelBiasDetected
              expr: |
                abs(trustyai_spd{model="{model_name}"}) > 0.1
              for: 15m
              labels:
                severity: warning
              annotations:
                summary: "Bias detected in model {{ $labels.model }}"
                description: "SPD value {{ $value }} exceeds threshold for {{ $labels.protected_attribute }}"
            - alert: DataDriftDetected
              expr: |
                trustyai_drift_meanshift{model="{model_name}"} > 0.25
              for: 30m
              labels:
                severity: warning
              annotations:
                summary: "Data drift detected for model {{ $labels.model }}"
                description: "Feature {{ $labels.feature }} drift score {{ $value }} exceeds threshold"
    ```

### Phase 7: Interpretation and Response

15. When bias or drift is detected, investigate:
    - Call `mcp_openshift` → `pods_log` for the TrustyAI service pod to get detailed metric history
    - Check if drift correlates with a data pipeline change or new data source
    - Determine if bias is systemic or transient (check trend over time)
16. Recommended responses:
    | Finding | Severity | Action |
    |---------|----------|--------|
    | SPD > 0.1 (sustained) | High | Investigate training data balance, consider retraining |
    | DIR < 0.8 (sustained) | High | Review model for discriminatory patterns |
    | Drift > 0.25 (single feature) | Medium | Check upstream data pipeline for changes |
    | Drift > 0.25 (multiple features) | High | Input distribution shifted — retrain with recent data |
    | Metrics not updating | Low | Check TrustyAI pod health and data collection |

17. Call `mcp_openshift` → `events_list` in the model namespace to check for:
    - TrustyAI reconciliation errors
    - Metric computation failures
    - Storage issues (TrustyAI stores inference data locally)

## Output Format

```
# Model Drift & Bias Report — {timestamp}

## TrustyAI Status
- Operator: {Running/Degraded}
- Service pod: {Running/Pending/Error}
- Data collected: {record_count} inference records
- Monitoring since: {start_date}

## Monitored Model
- Name: {inference_service_name}
- Namespace: {namespace}
- Runtime: {serving_runtime}
- Replicas: {count}

## Bias Metrics
| Metric | Attribute | Value | Threshold | Status |
|--------|-----------|-------|-----------|--------|
| SPD | {attribute} | {value} | ±0.1 | ✅/⚠️/🔴 |
| DIR | {attribute} | {value} | 0.8–1.25 | ✅/⚠️/🔴 |

## Data Drift Metrics
| Feature | Metric | Score | Threshold | Status | Trend |
|---------|--------|-------|-----------|--------|-------|
| {feature} | {metric} | {score} | {threshold} | ✅/⚠️/🔴 | ↑/↓/→ |

## Alert Configuration
| Alert | Expression | Status |
|-------|-----------|--------|
| ModelBiasDetected | abs(trustyai_spd) > 0.1 for 15m | {Active/Pending/Inactive} |
| DataDriftDetected | drift_meanshift > 0.25 for 30m | {Active/Pending/Inactive} |

## Findings
{Summary of current bias/drift status with interpretation}

## Recommendations
### Immediate
- {urgent actions if thresholds breached}

### Preventive
- {ongoing monitoring improvements}

### Model Lifecycle
- {retraining or version update suggestions}
```

## Safety Constraints

- Never disable bias monitoring without explicit user approval and documented justification
- Do not modify fairness thresholds to hide bias — only adjust if the domain justifies different bounds
- Bias metric results must be reported accurately — never suppress or round away concerning values
- Alert configurations must not be weakened (e.g., extending `for` duration) without explicit approval
- TrustyAI inference data may contain PII — do not expose raw prediction data in reports
- Do not recommend removing protected attributes from the model as a "fix" for bias
- All monitoring configuration changes must go through Git PRs — no direct kubectl mutations
- Clearly distinguish between statistical bias (metric) and confirmed discriminatory impact (requires human review)

## Disconnected Environment Notes

- TrustyAI operator images must be mirrored to the internal registry
- User workload monitoring (Prometheus) must be enabled in the cluster-monitoring-config ConfigMap
- PrometheusRule CRs require the user-workload-monitoring stack to be operational
- TrustyAI stores inference data in PVCs — ensure StorageClass is available for dynamic provisioning
- Alertmanager routing for bias alerts must use internal notification channels (no external webhooks in air-gapped)
- Dashboard visualization of TrustyAI metrics requires the Grafana instance to be configured with internal Prometheus as datasource
- Metric computation is local to the cluster — no external API calls required for bias/drift calculation
