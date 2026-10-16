# Spark + Kueue Resource-Contention POC

## What This Is

A set of **tested, validated YAML manifests** for Kueue-based admission control and gang
scheduling for batch Spark workloads on RHOAI 3.5. Each YAML maps to a specific test
case from the [POC document](docs/poc-kueue-spark-final.md). All manifests were
executed and validated on 2026-10-15 on RHOAI 3.5.1 / Spark Operator 2.4.0 / Kueue 1.4.3.

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
├── kueue-cluster-queue.yaml               # ClusterQueue — 25 CPU default (patch to 6 for TC-4)
├── kueue-local-queue.yaml                 # LocalQueue (spark-lq → spark-cq)
├── networkpolicy.yaml                     # Spark pod communication (RHOAIENG-53206)
├── tc1-baseline-no-kueue.yaml             # TC-1: Baseline — 33 CPU, no Kueue
├── tc2-kueue-admission-blocking.yaml      # TC-2: Same job, WITH Kueue label
├── tc3-gang-scheduling.yaml               # TC-3: Gang scheduling — 33 CPU exceeds 25 CPU quota
├── tc3-gang-scheduling-overflow.yaml       # TC-3: Optional overflow job
├── tc4a-large-job.yaml                    # TC-4: First job — 5 CPU (requires CQ patched to 6)
├── tc4b-queued-job.yaml                   # TC-4: Second job — auto-admits after first
├── tc5-dynamic-allocation.yaml            # TC-5: Rejected by Kueue webhook
├── tc6-retry-with-kueue.yaml             # TC-6: OnFailure + Kueue (zero churn)
├── tc6-retry-without-kueue.yaml          # TC-6: OnFailure, no Kueue (retry storm)
├── tc7-executor-failure.yaml             # TC-7: Kill an executor, watch Spark recover
└── docs/
    ├── poc-kueue-spark-resource-contention.md  # Full POC plan & research
    ├── poc-kueue-spark-final.md                # Final POC plan
    └── poc-kueue-spark-contention-evidence.md  # Test execution evidence
```

## How to Run Each Test Case

### Step 0 — Deploy Infrastructure (once)

```bash
# Apply Kueue infrastructure + NetworkPolicy
oc apply -k .
```

This creates the `ResourceFlavor`, `ClusterQueue` (25 CPU quota), `LocalQueue` (`spark-lq`), and `NetworkPolicy`.

> **IMPORTANT:** Use `default-flavor` ResourceFlavor. Custom-named flavors (e.g. `spark-rf`)
> were observed to cause spark-submit hangs during testing.

### TC-1: Baseline Reproduction (the problem)

```bash
oc apply -f tc1-baseline-no-kueue.yaml
oc get pods -l sparkoperator.k8s.io/app-name=tc1-baseline-no-kueue -w
# Observe: driver Running, executors Pending (half-admitted state)
# Cleanup:
oc delete sparkapplication tc1-baseline-no-kueue
```

### TC-2: Kueue Admission Blocking

```bash
oc apply -f tc2-kueue-admission-blocking.yaml
oc get sparkapplication tc2-kueue-admission-block -w
# Observe: stays Suspended, zero pods, Workload ADMITTED=False
oc get workload
# Cleanup:
oc delete sparkapplication tc2-kueue-admission-block
```

### TC-3: Gang Scheduling

```bash
oc apply -f tc3-gang-scheduling.yaml
oc get sparkapplication tc3-gang-scheduling -w
# Observe: stays Suspended — Kueue won't admit driver alone
# even though 25 CPU is available; it requires all 33 CPU
oc get pods -l sparkoperator.k8s.io/app-name=tc3-gang-scheduling
# Expect: zero pods — proves all-or-nothing admission
# Cleanup:
oc delete sparkapplication tc3-gang-scheduling
```

### TC-4: Quota Release & Re-Admission

```bash
# Step 1: Patch CQ quota to 6 CPU for this test
oc patch clusterqueue spark-cq --type merge \
  -p '{"spec":{"resourceGroups":[{"coveredResources":["cpu","memory"],"flavors":[{"name":"default-flavor","resources":[{"name":"cpu","nominalQuota":"6"},{"name":"memory","nominalQuota":"32Gi"}]}]}]}}'

# Step 2: Apply both jobs — tc4a runs (5 CPU < 6), tc4b waits (5+5=10 > 6)
oc apply -f tc4a-large-job.yaml
sleep 5
oc apply -f tc4b-queued-job.yaml

# Watch in two terminals:
oc get sparkapplication -w                    # terminal 1
oc get clusterqueue spark-cq -w              # terminal 2 (watch usedQuota)
# Measure: time from tc4a Completed → tc4b unsuspended

# Step 3: Cleanup + restore quota
oc delete sparkapplication tc4-job-a tc4-job-b
oc patch clusterqueue spark-cq --type merge \
  -p '{"spec":{"resourceGroups":[{"coveredResources":["cpu","memory"],"flavors":[{"name":"default-flavor","resources":[{"name":"cpu","nominalQuota":"25"},{"name":"memory","nominalQuota":"32Gi"}]}]}]}}'
```

### TC-5: Dynamic Allocation Rejection

```bash
oc apply -f tc5-dynamic-allocation.yaml
# Expect: admission webhook error on apply:
#   "a kueue managed job can use dynamicAllocation only when the
#    ElasticJobsViaWorkloadSlices feature gate is on and the job is an elastic job"
```

### TC-6: Retry Behavior Comparison

```bash
# Side A — WITH Kueue (zero churn)
oc apply -f tc6-retry-with-kueue.yaml
oc get pods -l sparkoperator.k8s.io/app-name=tc6-retry-with-kueue
# Expect: zero pods (job suspended by Kueue)

# Side B — WITHOUT Kueue (retry storm)
oc apply -f tc6-retry-without-kueue.yaml
oc get events --field-selector involvedObject.name=tc6-retry-no-kueue -w
# Expect: repeated pod creation/deletion events

# Cleanup:
oc delete sparkapplication tc6-retry-with-kueue tc6-retry-no-kueue
```

### TC-7: Individual Executor Failure

```bash
# Step 1: Submit a long-running job (SparkPi with 5000 partitions, ~4 minutes)
oc apply -f tc7-executor-failure.yaml
oc get pods -l sparkoperator.k8s.io/app-name=tc7-executor-failure -w
# Wait until driver + all 3 executors show Running

# Step 2: Kill one executor mid-job
EXEC_POD=$(oc get pods -l sparkoperator.k8s.io/app-name=tc7-executor-failure \
  --no-headers | grep exec-2 | awk '{print $1}')
oc delete pod $EXEC_POD --grace-period=0 --force

# Step 3: Watch for replacement executor
oc get pods -l sparkoperator.k8s.io/app-name=tc7-executor-failure -w
# Expect: exec-2 disappears, exec-4 appears within ~30 seconds

# Step 4: Verify recovery in driver logs
DRIVER_POD=$(oc get pods -l sparkoperator.k8s.io/app-name=tc7-executor-failure \
  --no-headers | grep driver | awk '{print $1}')
oc logs $DRIVER_POD | grep -E 'Lost executor|request.*executor|Registered executor'
# Expect: "Lost executor 2" → "request 1 executors" → "Registered executor ... ID 4"

# Step 5: Wait for job completion
oc get sparkapplication tc7-executor-failure -w
# Expect: COMPLETED with executionAttempts: 1

# Step 6: Check final executor states
oc get sparkapplication tc7-executor-failure \
  -o jsonpath='{.status.executorState}' | python3 -m json.tool
# Expect: exec-2 FAILED, exec-1/exec-3/exec-4 COMPLETED

# Cleanup:
oc delete sparkapplication tc7-executor-failure
```

## Test Case Summary

| Test Case | Total CPU | Kueue? | CQ Quota | Expected Outcome |
|---|---|---|---|---|
| TC-1 | 33 (1+4×8) | ❌ No | N/A | Half-admitted: driver runs, executors Pending |
| TC-2 | 33 (1+4×8) | ✅ Yes | 25 | Stays Suspended, zero pods |
| TC-3 | 33 (1+4×8) | ✅ Yes | 25 | All-or-nothing: entire job blocked |
| TC-4 | 5+5 (1+2×2) | ✅ Yes | 6 | Job B auto-admits when Job A finishes |
| TC-5 | Dynamic alloc | ✅ Yes | Any | Webhook rejects at creation |
| TC-6 | 9 (1+4×2) | Both | < 9 | Kueue: 0 pods; No Kueue: retry storm |
| TC-7 | 4 (1+3×1) | N/A | N/A | Kill executor → replaced in ~25s → job completes |

## Kueue Resource Computation for Spark

Kueue computes CPU demand using this precedence:
1. `coreRequest` if set (recommended — explicit)
2. `cores` if `coreRequest` is not set
3. `1` if neither is set

Memory overhead for Python: `max(0.4 × memory, 384Mi)` added automatically.

> **Tip:** Always set `coreRequest` explicitly to ensure Kueue's resource computation
> matches what `kube-scheduler` will request.

## Component Versions (Tested)

| Component | Version | RHOAI 3.5 Status |
|---|---|---|
| Kubeflow Spark Operator | 2.4.0 | GA |
| Apache Spark | 4.0.1 | GA |
| Red Hat build of Kueue Operator | 1.4.3 | GA |
| Kueue + SparkApplication integration | — | Technology Preview |

## Documentation

| Document | Description |
|---|---|
| [POC Plan (Full)](docs/poc-kueue-spark-resource-contention.md) | Complete feasibility analysis, research findings, and implementation task breakdown |
| [POC Plan (Final)](docs/poc-kueue-spark-final.md) | Cleaned-up POC plan with problem statement, test cases, component matrix, and engineering questions |
| [Execution Evidence](docs/poc-kueue-spark-contention-evidence.md) | Live test execution results for all 6 test cases with timestamps, pod statuses, and Kueue messages |
