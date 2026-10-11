# Spark + Kueue Resource-Contention POC

## What This Is

A set of **test-case YAMLs** for validating Kueue-based admission control and gang
scheduling for batch Spark workloads on RHOAI 3.5. Each YAML maps to a specific test
case from the [POC document](docs/poc-kueue-spark-resource-contention.md).

## The Problem

Without Kueue, a Spark job that requests more resources than available becomes
"half-admitted" — the driver runs, some executors stay Pending, resources are wasted,
and retry loops compound the problem. Kueue prevents this by holding the entire job
in Suspended state until the full resource set (driver + all executors) can be reserved.

## Prerequisites

1. **OpenShift 4.19+** with **RHOAI 3.5** installed
2. **Spark Operator** enabled (`sparkoperator: Managed` in DataScienceCluster)
3. **Red Hat build of Kueue Operator (v1.4+)** installed with SparkApplication framework and gang scheduling:
   ```yaml
   # oc edit kueue cluster -n openshift-kueue-operator
   # API: kueue.openshift.io/v1
   apiVersion: kueue.openshift.io/v1
   kind: Kueue
   metadata:
     name: cluster
     namespace: openshift-kueue-operator
   spec:
     managementState: Managed
     config:
       integrations:
         frameworks:
         - BatchJob
         - sparkoperator.k8s.io/sparkapplication
       # Enable gang scheduling (disabled by default — Red Hat docs Section 2.15)
       gangScheduling:
         policy: ByWorkload
         byWorkload:
           admission: Sequential
   ```
   > **Requires RHBoK 1.4+** (Kueue 0.18). RHBoK 1.3 (Kueue 0.16) does not include
   > the SparkApplication reconciler. If the cluster also uses Kubeflow Trainer v2,
   > note that RHBoK 1.4 breaks Trainer v2 integration (RHOAI known issue RHOAIENG-87625).
4. **Namespace labeled** for Kueue management:
   ```bash
   oc label namespace <ns> kueue.openshift.io/managed=true --overwrite
   ```
5. **Webhook patched** to include target namespace (see [spark-data-ingestion README](../spark-data-ingestion/README.md#1-webhook-namespace-selector))
6. **Kueue RBAC** for SparkApplication finalizers (see [verification guide](../spark-data-ingestion/docs/kueue-spark-verification.md#8-kueue-rbac-for-sparkapplication-finalizers))

## File Inventory

```
spark-kueue-contention-poc/
├── kustomization.yaml                     # Kustomize entry point (uncomment test cases)
├── README.md                              # This file
├── kueue-resource-flavor.yaml             # ResourceFlavor (default node pool)
├── kueue-cluster-queue.yaml               # ClusterQueue — deliberately constrained (4 CPU)
├── kueue-local-queue.yaml                 # LocalQueue in target namespace
├── networkpolicy.yaml                     # Spark pod communication (RHOAIENG-53206)
├── tc1-baseline-no-kueue.yaml             # TC-1: Baseline — 10 CPU, no Kueue
├── tc2-kueue-admission-blocking.yaml      # TC-2: Same job, WITH Kueue label
├── tc3-gang-scheduling.yaml               # TC-3: Gang scheduling (fits in quota)
├── tc3-gang-scheduling-overflow.yaml       # TC-3: Second job (proves no partial admit)
├── tc4a-large-job.yaml                    # TC-4: First job (consumes all quota)
├── tc4b-queued-job.yaml                   # TC-4: Second job (auto-admits after first)
├── tc5-dynamic-allocation.yaml            # TC-5: Rejected by Kueue webhook
├── tc6-retry-with-kueue.yaml             # TC-6: OnFailure + Kueue (zero churn)
├── tc6-retry-without-kueue.yaml          # TC-6: OnFailure, no Kueue (retry storm)
└── docs/
    └── poc-kueue-spark-resource-contention.md  # Full POC document
```

## How to Run Each Test Case

### Step 0 — Deploy Infrastructure (once)

```bash
# Apply Kueue infrastructure + NetworkPolicy
oc apply -k .
```

This creates the `ResourceFlavor`, `ClusterQueue` (4 CPU quota), `LocalQueue`, and `NetworkPolicy`.

### TC-1: Baseline Reproduction (the problem)

```bash
oc apply -f tc1-baseline-no-kueue.yaml
oc get pods -l sparkoperator.k8s.io/app-name=tc1-baseline-no-kueue -w
# Observe: driver runs, most executors Pending, job hangs
# Cleanup:
oc delete sparkapplication tc1-baseline-no-kueue
```

### TC-2: Kueue Admission Blocking

```bash
oc apply -f tc2-kueue-admission-blocking.yaml
oc get sparkapplication tc2-kueue-admission-blocking -w
# Observe: stays Suspended, zero pods, Workload ADMITTED=False
oc get workload
# Cleanup:
oc delete sparkapplication tc2-kueue-admission-blocking
```

### TC-3: Gang Scheduling

```bash
# Job 1 — fits in quota, runs immediately
oc apply -f tc3-gang-scheduling.yaml
oc get sparkapplication tc3-gang-scheduling -w
# Wait until Running, then apply the overflow:
oc apply -f tc3-gang-scheduling-overflow.yaml
oc get sparkapplication tc3-gang-overflow -w
# Observe: overflow stays Suspended (not half-admitted)
# When tc3-gang-scheduling completes → tc3-gang-overflow auto-admits
# Cleanup:
oc delete sparkapplication tc3-gang-scheduling tc3-gang-overflow
```

### TC-4: Quota Release & Re-Admission

```bash
# Apply both — tc4a runs, tc4b waits
oc apply -f tc4a-large-job.yaml
sleep 5
oc apply -f tc4b-queued-job.yaml
# Watch in two terminals:
oc get sparkapplication -w                    # terminal 1
oc get clusterqueue contention-cq -w          # terminal 2 (watch usedQuota)
# Measure: time from tc4a Completed → tc4b unsuspended
# Cleanup:
oc delete sparkapplication tc4a-large-job tc4b-queued-job
```

### TC-5: Dynamic Allocation Rejection

```bash
oc apply -f tc5-dynamic-allocation.yaml
# Expect: admission webhook error on apply
# Capture the error message for the report
```

### TC-6: Retry Behavior Comparison

```bash
# Side A — WITH Kueue (zero churn)
oc apply -f tc6-retry-with-kueue.yaml
oc get pods -l sparkoperator.k8s.io/app-name=tc6-retry-with-kueue
# Expect: zero pods

# Side B — WITHOUT Kueue (retry storm)
oc apply -f tc6-retry-without-kueue.yaml
oc get events --field-selector involvedObject.name=tc6-retry-without-kueue -w
# Expect: repeated pod creation/deletion events

# Cleanup:
oc delete sparkapplication tc6-retry-with-kueue tc6-retry-without-kueue
```

## Test Case Summary

| Test Case | Resources | Kueue? | Expected Outcome |
|---|---|---|---|
| TC-1 | 10 CPU (2+4×2) | ❌ No | Half-admitted: driver runs, executors Pending |
| TC-2 | 10 CPU (2+4×2) | ✅ Yes | Stays Suspended, zero pods |
| TC-3 | 4 CPU (1+3×1) | ✅ Yes | First job admitted; overflow blocked entirely |
| TC-4 | 4 CPU + 3 CPU | ✅ Yes | Job B auto-admits when Job A finishes |
| TC-5 | Dynamic alloc | ✅ Yes | Webhook rejects at creation |
| TC-6 | 10 CPU + retries | Both | Kueue: 0 pods; No Kueue: retry storm |

## Component Versions

| Component | Version | RHOAI 3.5 Status |
|---|---|---|
| Kubeflow Spark Operator | 2.4.0 | GA |
| Apache Spark | 4.0.1 | GA |
| Red Hat build of Kueue Operator | — | GA |
| Kueue + SparkApplication integration | — | Technology Preview |

## Full POC Document

See [docs/poc-kueue-spark-resource-contention.md](docs/poc-kueue-spark-resource-contention.md) for the
complete feasibility analysis, research findings, and implementation task breakdown.
