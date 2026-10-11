# POC: Kueue on OpenShift — Resource-Contention Protection for Batch Spark Workloads

## Document Purpose

This document captures a POC (Proof of Concept) use case for validating **Kueue-based admission control and gang scheduling** for batch Spark workloads managed by the **Kubeflow Spark Operator** on **Red Hat OpenShift AI (RHOAI) 3.5**.

The goal is to determine whether Kueue can prevent the "half-admitted, resource-wasting" failure mode that occurs when Spark jobs are submitted without admission control into a resource-constrained cluster.

> **Environment ask:** Pre-staged setup in eLab (interim), transitioning to iLab once app-team access is provisioned.

---

## 1. Background

The team currently runs Spark batch workloads on OpenShift. As part of a Phase 1 POC, the objective is to validate two platform capabilities:

1. **Kubeflow Spark Operator (KSO)** — declarative, Kubernetes-native submission and lifecycle management of Spark jobs via `SparkApplication` / `ScheduledSparkApplication` CRDs, replacing ad-hoc `spark-submit` scripts and client-mode submission.

2. **Kueue** — quota-based admission control and gang scheduling for batch workloads sharing a common OpenShift resource pool.

The current approach was evaluated against the Operator pattern, and a concrete, business-relevant risk scenario was identified for validation in a controlled POC environment before recommending broader adoption.

---

## 2. Problem Statement (The Risk Scenario)

**Observed/anticipated failure mode:** A Spark job is submitted requesting more aggregate resources (e.g., 10 CPU across driver + executors) than are currently available in the cluster (e.g., only 2 CPU free). Today, without any admission-control layer:

- The Spark Operator creates the Driver and Executor pods **without any upfront capacity check**.
- The `kube-scheduler` schedules pods **independently, one at a time** — the Driver (small footprint) and a subset of Executors that fit are scheduled and start Running, while the remaining Executors are left in Pending.
- The job does not fail outright; instead, it becomes **"half-admitted"** — partially running, partially stuck — and the Driver waits indefinitely (or until a timeout) for the missing Executors.
- If the `SparkApplication`'s `restartPolicy` is configured to retry on failure, this can escalate into a **retry loop**, repeatedly creating and tearing down pods, compounding the resource waste.
- The net effect: compute resources (CPU/memory already allocated to the Driver and the partially-scheduled Executors) are **held and effectively wasted** for the duration of the stuck/retrying job, reducing capacity available to other tenants/jobs in the same namespace or cluster.

### Why this matters

As more Spark batch workloads are consolidated onto a shared OpenShift cluster (multi-tenant model), the probability of concurrent job submissions exceeding available capacity increases. Without admission control, a single oversized or mistimed submission can degrade the experience for other workloads sharing the same `ClusterQueue`/namespace — an operationally expensive and hard-to-diagnose failure mode.

### Evidence gathering

A read-only investigation (`oc get events`, `oc get job`, `oc describe job`) was performed against a production namespace. While no `FailedScheduling` events were found in the current 1-hour event retention window, a historical cluster of three batch Jobs that failed within roughly 90 minutes of each other was identified (each with `status.failed=1, succeeded=0`), consistent with a resource-contention pattern during a concentrated batch window.

Full root-cause confirmation was not possible because Kubernetes Events (1-hour TTL) had already expired, and long-retention monitoring (Prometheus/Thanos) or log aggregation (Splunk/ELK) was not available for this namespace. These batch jobs are treated as a **representative example** of the resource profile and timing pattern to validate against — not as confirmed root cause — and the POC reproduction uses similar resource specifications.

---

## 3. What We Want to Validate

### Phase 1 — Spark Operator: Production-Readiness Baseline

Confirm that migrating from script-based `spark-submit` to the declarative `SparkApplication` CRD works as expected:

- Declarative submission (`oc apply -f sparkapplication.yaml`) successfully creates Driver + Executor pods and completes a representative batch job.
- Spark History Server correctly captures event logs for post-run analysis (stage timeline, executor utilization, shuffle metrics).
- Pod-level metrics are exportable to Prometheus/Grafana (standard OpenShift observability stack).
- `restartPolicy` behavior is observed and documented when a Driver pod fails or is deleted.

### Phase 2 — Kueue: Admission Control & Resource-Contention Protection

This is the core of the risk-mitigation validation, directly addressing the problem statement above.

| Test Case | Setup | Expected Result (with Kueue) | Baseline Result (without Kueue, for comparison) |
|---|---|---|---|
| **TC-1: Baseline reproduction** | Submit a `SparkApplication` requesting 10 CPU (driver + executors) into a `ClusterQueue`/namespace throttled to only 2 CPU available, **without** Kueue admission | N/A (baseline) | Driver pod schedules and runs; some/all Executor pods remain Pending; job does not complete; resources held indefinitely or until manual/timeout intervention |
| **TC-2: Kueue admission blocking** | Same job submitted with `kueue.x-k8s.io/queue-name` label, insufficient `ClusterQueue` quota | `SparkApplication` remains **Suspended**; zero Driver/Executor pods are created until quota is available | — |
| **TC-3: Gang scheduling** | Construct a scenario where quota is short by exactly one Executor's worth of resources | Kueue does **not** partially admit (no "Driver + some Executors" half-state); job stays queued until full resource set is available | — |
| **TC-4: Quota release & re-admission** | Run a large job that consumes available quota; queue a second smaller job behind it | Once the first job completes, quota is released and the second job is automatically admitted without manual intervention; measure queue wait time | — |
| **TC-5: Dynamic Allocation compatibility check** | Submit a `SparkApplication` with `spark.dynamicAllocation.enabled=true` under Kueue management | Allocation is **not supported** in combination with **Kueue** in RHOAI 3.5 (Technology Preview); executor count must be fixed | — |
| **TC-6: Failure/retry behavior comparison** | Compare pod creation/teardown churn with `restartPolicy: OnFailure` with and without Kueue, under resource contention | With Kueue: no retry churn occurs because the job never starts until quota is available | Without Kueue: repeated pod creation/failure cycles possible, compounding resource waste |

### Success Criteria

- **TC-2 and TC-3** demonstrate that Kueue prevents the "partially-scheduled, resource-wasting" state entirely — this is the primary validation goal.
- **TC-4** produces a measurable, acceptable queue-wait time for production planning purposes.
- **TC-5 and TC-6** produce documented constraints/behaviors that can factor into the production rollout decision.

---

## 4. Proposed Reference Configuration

The request is for the OpenShift Engineering team to stand up the following in the interim eLab environment (pending iLab access provisioning), using the Kubeflow Spark Operator + Red Hat build of Kueue:

- **Base workload pattern**: a representative PySpark batch job (driver + 1–2 executors, similar resource shape to production batch jobs — approximate CPU/memory request values can be provided for realism).

- **Three submission variants**, consistent with Spark Operator's standard GA/Tech Preview modes:
  1. `SparkApplication` — single run (**GA**)
  2. `SparkApplication` + `kueue.x-k8s.io/queue-name` label — Kueue-managed (**Kueue integration: Technology Preview in RHOAI 3.5**)
  3. `ScheduledSparkApplication` — cron-based recurring run (functionally available but **not officially listed as supported** in RHOAI 3.5 release notes; flagged here for awareness, not required for Phase 1 Kueue validation)

- **Supporting infrastructure**: `ClusterQueue` with a deliberately constrained CPU quota (to reproduce the contention scenario on demand), `LocalQueue` in the target namespace, and Spark History Server for post-run observability.

- **Prerequisites on the OpenShift side**: Spark Operator webhook `namespaceSelector` patched to include the target namespace; `NetworkPolicy` permitting Driver↔Executor communication (ports 7078/7079/4040) if the namespace has default-deny ingress rules.

Ready-to-apply YAML manifests for all of the above (`SparkApplication`, Kueue-labeled variant, `ClusterQueue`/`LocalQueue`, and the supporting PVCs/ConfigMaps) can be supplied to accelerate setup.

---

## 5. Deliverable

A walkthrough/demo session (as proposed) covering:

1. Live reproduction of TC-1 (the problem) vs. TC-2/TC-3 (Kueue's mitigation) side by side.
2. Observed queue wait time and quota reclamation behavior (TC-4).
3. A clear statement of constraints (TC-5 Dynamic Allocation limitation) and support-level caveats (Kueue + SparkApplication integration is Technology Preview in RHOAI 3.5) so an informed production-adoption recommendation can be made to leadership.

---

## 6. Feasibility Analysis — Research Findings

The following analysis is based on official Red Hat documentation, upstream Kueue docs, and Kubeflow Spark Operator source code as of October 2026.

### 6.1 Component Support Matrix in RHOAI 3.5

| Component | RHOAI 3.5 Status | Version | Notes |
|---|---|---|---|
| Kubeflow Spark Operator | **GA** | 2.4.0 | Was TP in RHOAI 3.4; now GA in 3.5 |
| Apache Spark | **GA** | 4.0.1 | Bundled with KSO |
| Red Hat build of Kueue | **GA** | — | Provided via Red Hat build of Kueue Operator (replaces deprecated embedded Kueue) |
| **Kueue + SparkApplication integration** | **Technology Preview** | — | Explicitly listed as TP in [RHOAI 3.5 release notes](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/release_notes/technology-preview-features_relnotes): *"SparkApplication workloads managed by the Kubeflow Spark Operator (KSO) can be admitted and scheduled through Kueue"* |
| ScheduledSparkApplication | **Not explicitly documented** | — | The Spark Operator supports it (CRD is installed, [upstream docs](https://spark.kubeflow.org/en/latest/user-guide/running-sparkapplication-on-schedule.html) cover it), and RHOAI 3.5 mentions "Native Cron support for running scheduled applications" — but it is not separately called out in RHOAI 3.5 release notes as a GA or TP feature |
| Spark Connect | **Technology Preview** | — | For interactive workbench workflows; not relevant to this batch POC |

**Source:** [Red Hat OpenShift AI: Supported Configurations for 3.x](https://access.redhat.com/articles/rhoai-supported-configs-3.x)

### 6.2 Test Case Feasibility Assessment

#### TC-1: Baseline reproduction (without Kueue) — ✅ FEASIBLE

This is a straightforward `SparkApplication` submission without the Kueue queue-name label. The Spark Operator will create Driver and Executor pods immediately. The `kube-scheduler` will schedule what it can; pods that don't fit will stay `Pending`. This is the existing default behavior and requires no special configuration.

**How to set up:**
- Deploy a `SparkApplication` with `driver.coreRequest: "2"` + `executor.instances: 4, executor.coreRequest: "2"` = 10 CPU total
- Ensure the namespace/node pool has only 2 CPU available via `ResourceQuota` or node constraints
- Observe: Driver runs, 0–1 Executors schedule, remaining Executors stay `Pending`, job hangs

#### TC-2: Kueue admission blocking — ✅ FEASIBLE

This is the core Kueue use case and is explicitly supported as a Technology Preview feature in RHOAI 3.5.

**How it works** ([upstream Kueue docs](https://kueue.sigs.k8s.io/docs/tasks/run/kubeflow/sparkapplications/)):
1. Kueue's webhook intercepts the `SparkApplication` creation and sets `spec.suspend: true`
2. Kueue creates a `Workload` object representing the total resource demand (driver + all executors)
3. Kueue evaluates the `Workload` against the `ClusterQueue` quota
4. If insufficient quota → `SparkApplication` stays `Suspended`, zero pods are created
5. When quota becomes available → Kueue sets `spec.suspend: false`, Spark Operator creates pods

**Prerequisites (Kueue configuration):**

Add SparkApplication to the Kueue CR's `integrations.frameworks` (same pattern as LeaderWorkerSet/JobSet in Red Hat docs):
```yaml
# oc edit kueue cluster -n openshift-kueue-operator
spec:
  config:
    integrations:
      frameworks:
      - BatchJob
      - sparkoperator.k8s.io/sparkapplication
```

> **Requires RHBoK 1.4+** (Kueue 0.18). The Red Hat Kueue CR does not expose a `featureGates` field — the operator enables the SparkApplication reconciler automatically when it sees the framework in the list.

**SparkApplication must include:**
```yaml
metadata:
  labels:
    kueue.x-k8s.io/queue-name: <local-queue-name>
```

> ⚠️ **Important:** Both the `SparkApplicationIntegration` feature gate AND the framework entry in `integrations.frameworks` must be configured. The feature gate enables webhooks/RBAC, but the framework registration is what starts the Kueue reconciler. See [kubernetes-sigs/kueue#10483](https://github.com/kubernetes-sigs/kueue/issues/10483).

**Kueue resource computation for Spark:**
- CPU: `coreRequest` if set, otherwise `cores`, otherwise `1`
- Memory: `memory` (default `1g`) + `memoryOverhead`. If overhead not set: `max(memoryOverheadFactor × memory, 384m)`, where factor defaults to `0.1` (Java/Scala) or `0.4` (Python/R)

#### TC-3: Gang scheduling (all-or-nothing admission) — ✅ FEASIBLE

Kueue provides **two layers** of all-or-nothing behavior:

**Layer 1 — Quota reservation (always on):** By default, Kueue only unsuspends a Workload when quota for ALL pod sets can be reserved at once. This prevents partial admission at the quota level.

**Layer 2 — Gang scheduling (must be enabled):** Per the [Red Hat build of Kueue docs (OCP 4.22, Section 2.15)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/ai_workloads/red-hat-build-of-kueue):

> *"Red Hat build of Kueue enables gang scheduling by suspending jobs until the OpenShift Container Platform cluster can guarantee the capacity to start and execute all of the related jobs in the gang together."*

**Gang scheduling is disabled by default.** To enable it, configure the `Kueue` CR:

```yaml
apiVersion: kueue.openshift.io/v1
kind: Kueue
metadata:
  name: cluster
  namespace: openshift-kueue-operator
spec:
  config:
    gangScheduling:
      policy: ByWorkload            # Default is None (disabled)
      byWorkload:
        admission: Sequential       # Or Parallel (faster but can deadlock)
```

| Policy | Behavior |
|---|---|
| `ByWorkload` | Each job processed as a single unit; if pods don't become Ready in time, the **entire job is evicted and retried** |
| `None` | Gang scheduling disabled — quota-level all-or-nothing still works, but no eviction safety net |
| `Sequential` admission | Only pods from the current job are admitted at a time (prevents deadlocks) |
| `Parallel` admission | Pods from any job can be admitted at any time (faster, but deadlock risk) |

For a `SparkApplication`, Kueue constructs a `Workload` with two pod sets:
1. **Driver pod set** (1 pod)
2. **Executor pod set** (N pods, per `executor.instances`)

With quota reservation alone (Layer 1), if quota covers the driver + all executors, the job is admitted. With gang scheduling enabled (Layer 2), if admitted pods don't become Ready within the timeout, the entire job is evicted and requeued.

#### TC-4: Quota release & re-admission — ✅ FEASIBLE

This is standard Kueue behavior. When a workload finishes (SparkApplication completes or fails), Kueue releases the reserved quota. The next highest-priority queued workload is then evaluated and admitted if quota fits.

**How to demonstrate:**
1. Submit Job A (consumes all quota) with `kueue.x-k8s.io/queue-name` label
2. Submit Job B (also needs quota) — Kueue keeps it `Suspended`
3. Job A completes → Kueue auto-admits Job B
4. Measure: time between Job A completion and Job B unsuspension (the "queue wait time")

**Priority handling:** If multiple workloads are queued, Kueue respects `kueue.x-k8s.io/priority-class` or Kubernetes `PriorityClass` for ordering.

#### TC-5: Dynamic Allocation + Kueue — ✅ FEASIBLE TO DOCUMENT (confirms the limitation)

**This is explicitly NOT supported.** The Kueue webhook will **reject** any `SparkApplication` with `spec.dynamicAllocation.enabled: true` when it carries a `kueue.x-k8s.io/queue-name` label.

From the [upstream Kueue docs](https://kueue.sigs.k8s.io/docs/tasks/run/kubeflow/sparkapplications/):
> *"SparkApplication integration does not support dynamic allocation. If you set `spec.dynamicAllocation.enabled=true` in SparkApplication, Kueue will reject such resources in the webhook."*

From the [webhook source code](https://github.com/kubernetes-sigs/kueue/blob/22553e54/pkg/controller/jobs/sparkapplication/sparkapplication_webhook.go):
```go
if !isAnElasticJob(job) && ptr.Deref(spec.DynamicAllocation, ...).Enabled {
    allErrors = append(allErrors,
        field.Invalid(dynamicAllocationEnabledPath, ...,
            "a kueue managed job can use dynamicAllocation only when the
             ElasticJobsViaWorkloadSlices feature gate is on and the job
             is an elastic job"))
}
```

**Workaround:** Not applicable in RHOAI 3.5 TP. The upstream `ElasticJobsViaWorkloadSlices` feature gate exists but is not available in the Red Hat build of Kueue at this support level. Executor count **must be fixed** for Kueue-managed SparkApplications.

**POC action:** Submit a `SparkApplication` with `dynamicAllocation.enabled: true` + Kueue label → observe the rejection error → document the limitation.

#### TC-6: Failure/retry behavior comparison — ✅ FEASIBLE

**With Kueue:** If quota is insufficient, the `SparkApplication` stays `Suspended` (no pods created). No retry loop occurs because the Spark Operator never gets to create pods. This eliminates pod creation/teardown churn under contention.

**Without Kueue:** The Spark Operator creates pods immediately. If `restartPolicy.type: OnFailure` is set, and the job fails due to missing executors (timeout or Driver crash), the operator will retry, creating a fresh set of pods — which again partially schedule and fail, compounding waste.

**How to demonstrate:**
1. **Without Kueue:** Submit job with `restartPolicy: {type: OnFailure, onFailureRetries: 3}` into a resource-starved namespace. Count pod creation events over time.
2. **With Kueue:** Same job with Kueue label. Observe: zero pods created, `SparkApplication` stays `Suspended`, zero retry churn.

### 6.3 Additional Constraints & Caveats

| Constraint | Detail |
|---|---|
| **Kueue + SparkApplication is Technology Preview** | No Red Hat production SLA. May not be functionally complete. Not recommended for production use. Provides early access for testing and feedback. ([source](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/release_notes/technology-preview-features_relnotes)) |
| **SparkApplication framework enablement** | Not documented in Red Hat Kueue docs but follows the same pattern as LeaderWorkerSet/JobSet: add `sparkoperator.k8s.io/sparkapplication` to `integrations.frameworks` in the Kueue CR. Confirmed valid by the [upstream Kueue API reference](https://kueue.sigs.k8s.io/docs/reference/kueue-config.v1beta2/). Requires RHBoK 1.4+ (Kueue 0.18). |
| **Gang scheduling disabled by default** | Per [Red Hat docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/ai_workloads/red-hat-build-of-kueue), gang scheduling requires explicit `gangScheduling.policy: ByWorkload` in the Kueue CR. Without it, Kueue still does quota-level all-or-nothing but will NOT evict/retry jobs whose pods fail to become Ready. |
| **Only `cluster` mode supported** | Kueue rejects SparkApplications in `client` mode. The webhook validates: `spec.mode` must be `cluster`. |
| **Spark type / mainApplicationFile mismatch** | Kueue uses `spec.type` to determine Python/R overhead factor; Spark uses the file extension of `spec.mainApplicationFile`. If they disagree, the memory overhead Kueue reserves will differ from what Spark actually requests. Ensure they match. |
| **Pod template resources ignored** | Resources set via `spark.kubernetes.driver.podTemplateFile` / `spark.kubernetes.executor.podTemplateFile` are **not** accounted for by Kueue's quota computation. Use the typed `driver`/`executor` spec fields. |
| **ScheduledSparkApplication + Kueue** | Not explicitly documented or tested upstream. Each `ScheduledSparkApplication` creates child `SparkApplication` objects on a cron schedule. If those children carry the Kueue label (via the template), Kueue should manage them — but this interaction is untested in the RHOAI TP scope. |
| **Red Hat build of Kueue migration** | Starting RHOAI 2.24, embedded Kueue is deprecated. RHOAI 3.5 requires the Red Hat build of Kueue Operator (`Unmanaged` management state). Migration must happen before enabling Kueue. ([source](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/managing_openshift_ai/managing-workloads-with-kueue)) |
| **`PodsReady` executor bug** | Early SparkApplication integration had a bug where `PodsReady` only checked driver state ([#11675](https://github.com/kubernetes-sigs/kueue/issues/11675), fixed in [#11676](https://github.com/kubernetes-sigs/kueue/pull/11676)). Must verify the Red Hat Kueue build includes this fix. |

---

## 7. Implementation Task Breakdown

### Phase 0: Environment Setup

| # | Task | Owner | Effort | Notes |
|---|---|---|---|---|
| 0.1 | Provision eLab OpenShift 4.19+ cluster (or confirm existing) | Platform team | — | Minimum: 4.19.9+, RHCOS worker nodes |
| 0.2 | Install RHOAI 3.5 Operator | Platform team | 30 min | Set `sparkoperator` component to `Managed` in `DataScienceCluster` |
| 0.3 | Verify Spark Operator deployment | Platform team | 10 min | `oc get deployment -n redhat-ods-applications` — confirm controller + webhook running |
| 0.4 | Install Red Hat build of Kueue Operator | Platform team | 30 min | From OperatorHub; set `DataScienceCluster.spec.components.kueue.managementState: Unmanaged` |
| 0.5 | Enable SparkApplication integration in Kueue | Platform team | 15 min | Add `sparkoperator.k8s.io/sparkapplication` to `integrations.frameworks` in the `Kueue` CR. Requires RHBoK 1.4+. |
| 0.6 | Create target namespace with RBAC | Platform team | 15 min | Namespace with `kueue.openshift.io/managed=true` label, `spark-operator-spark` ServiceAccount, Role, RoleBinding |
| 0.7 | Patch webhook `namespaceSelector` | Platform team | 10 min | Ensure Spark Operator's mutating webhook covers the target namespace |
| 0.8 | Configure `NetworkPolicy` | Platform team | 10 min | Allow Driver↔Executor on ports 7078, 7079, 4040 if namespace has default-deny |

### Phase 1: Spark Operator Baseline (TC-1 adjacent)

| # | Task | Owner | Effort | Notes |
|---|---|---|---|---|
| 1.1 | Build custom Spark image (or use RHOAI-provided) | App team | 1 hr | Must include Spark 4.0.1 runtime; base from `registry.redhat.io` images |
| 1.2 | Create `SparkApplication` CR (PySpark batch job) | App team | 30 min | Match production resource profile: driver 2 CPU/2Gi, executors 2 CPU/2Gi × 4 |
| 1.3 | Submit and validate end-to-end | App team | 30 min | `oc apply -f sparkapplication.yaml`; verify pods, logs, completion |
| 1.4 | Deploy Spark History Server | App team | 1 hr | S3-compatible storage or PV for event logs; configure `spark.eventLog.dir` |
| 1.5 | Validate Prometheus metrics export | Platform team | 30 min | Confirm driver/executor metrics visible in Prometheus/Grafana |
| 1.6 | Document `restartPolicy` behavior | App team | 30 min | Test `Never`, `OnFailure` with manual driver pod deletion |

### Phase 2: Kueue Integration (TC-2 through TC-6)

| # | Task | Owner | Effort | Notes |
|---|---|---|---|---|
| 2.1 | Create `ClusterQueue` with constrained quota | Platform team | 15 min | E.g., `nominalQuota: {cpu: 4}` to force contention |
| 2.2 | Create `ResourceFlavor` + `LocalQueue` | Platform team | 15 min | Default flavor; `LocalQueue` in target namespace |
| 2.3 | Configure `waitForPodsReady` | Platform team | 10 min | `timeout: 5m`, `blockAdmission: true` as safety net |
| 2.4 | **TC-1**: Submit SparkApplication WITHOUT Kueue label | App team | 30 min | Reproduce the half-admitted state; document pod states |
| 2.5 | **TC-2**: Submit same SparkApplication WITH Kueue label | App team | 30 min | Verify: stays `Suspended`, zero pods, Kueue `Workload` object created |
| 2.6 | **TC-3**: Reduce quota to fit driver + N-1 executors | App team | 30 min | Verify: entire workload stays queued (no partial admission) |
| 2.7 | **TC-4**: Queue two jobs, wait for release/re-admission | App team | 30 min | Measure queue wait time between Job A completion → Job B admission |
| 2.8 | **TC-5**: Submit with `dynamicAllocation.enabled: true` | App team | 15 min | Verify: webhook rejection; capture error message |
| 2.9 | **TC-6**: Compare pod churn with/without Kueue under contention | App team | 30 min | Count pod creation events; compare `restartPolicy: OnFailure` behavior |
| 2.10 | Document all findings, screenshots, timing data | App team | 2 hr | Consolidate into presentation/report |

### Phase 3: Demo & Report

| # | Task | Owner | Effort | Notes |
|---|---|---|---|---|
| 3.1 | Prepare live walkthrough: TC-1 vs TC-2/TC-3 | App team | 1 hr | Side-by-side terminal or dashboard view |
| 3.2 | Present TC-4 queue wait time analysis | App team | 30 min | Include timing measurements |
| 3.3 | Present TC-5/TC-6 constraints document | App team | 30 min | Dynamic Allocation limitation, TP caveats |
| 3.4 | Production-adoption recommendation | App team + Platform | 1 hr | Go/no-go for Kueue + Spark in production; risk register update |

---

## 8. Kueue + SparkApplication Setup Reference

### 8.1 Kueue Configuration (on Red Hat build of Kueue)

The `Kueue` CR must be updated to add SparkApplication as a managed framework AND enable gang scheduling. This follows the same pattern Red Hat documents for LeaderWorkerSet and JobSet — add the framework string to `integrations.frameworks`.

The upstream [Kueue Configuration API reference](https://kueue.sigs.k8s.io/docs/reference/kueue-config.v1beta2/) confirms `sparkoperator.k8s.io/sparkapplication` is a valid framework value.

**Requires RHBoK 1.4+** (Kueue 0.18). RHBoK 1.3 (Kueue 0.16) does not include the SparkApplication reconciler code.

```yaml
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
    gangScheduling:
      policy: ByWorkload
      byWorkload:
        admission: Sequential
```

> **Note:** The Red Hat Kueue CR (`kueue.openshift.io/v1`) does not expose a `featureGates`
> field. The Red Hat operator handles feature gate enablement internally when it detects the
> framework in the `integrations.frameworks` list — same as it does for LeaderWorkerSet and JobSet.
>
> **Known issue (RHOAIENG-87625):** RHBoK 1.4 breaks Kubeflow Trainer v2 integration.
> If the cluster also uses Trainer v2, it cannot share the same RHBoK instance.

### 8.2 Queue Hierarchy

```yaml
apiVersion: kueue.x-k8s.io/v1beta2
kind: ResourceFlavor
metadata:
  name: default-flavor
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: ClusterQueue
metadata:
  name: spark-cluster-queue
spec:
  namespaceSelector: {}
  resourceGroups:
  - coveredResources: ["cpu", "memory"]
    flavors:
    - name: default-flavor
      resources:
      - name: "cpu"
        nominalQuota: 4           # Deliberately constrained for POC
      - name: "memory"
        nominalQuota: 8Gi
---
apiVersion: kueue.x-k8s.io/v1beta2
kind: LocalQueue
metadata:
  name: spark-local-queue
  namespace: <target-namespace>
spec:
  clusterQueue: spark-cluster-queue
```

### 8.3 SparkApplication with Kueue Label

```yaml
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: spark-batch-poc
  labels:
    kueue.x-k8s.io/queue-name: spark-local-queue   # ← Kueue management
spec:
  type: Python
  mode: cluster
  sparkVersion: "4.0.1"
  image: <spark-image>:4.0.1
  imagePullPolicy: IfNotPresent
  mainApplicationFile: local:///app/scripts/run_batch_job.py
  driver:
    coreRequest: "2"
    memory: 2g
    serviceAccount: spark-operator-spark
  executor:
    instances: 4
    coreRequest: "2"
    memory: 2g
  restartPolicy:
    type: Never
```

### 8.4 Namespace Prerequisites

```bash
# Label for Kueue enforcement
oc label namespace <target-namespace> kueue.openshift.io/managed=true

# Verify ServiceAccount exists (created by Spark Operator)
oc get sa spark-operator-spark -n <target-namespace>

# NetworkPolicy (if default-deny exists)
cat <<EOF | oc apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: spark-driver-executor
  namespace: <target-namespace>
spec:
  podSelector:
    matchLabels:
      sparkoperator.k8s.io/launched-by-spark-operator: "true"
  ingress:
  - from:
    - podSelector:
        matchLabels:
          sparkoperator.k8s.io/launched-by-spark-operator: "true"
    ports:
    - port: 7078
    - port: 7079
    - port: 4040
  policyTypes:
  - Ingress
EOF
```

---

## 9. Reference Links

| Resource | URL |
|---|---|
| RHOAI 3.5 Release Notes — Tech Preview Features | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/release_notes/technology-preview-features_relnotes |
| RHOAI 3.5 — Manage workloads with Kueue | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/managing_openshift_ai/managing-workloads-with-kueue |
| RHOAI 3.5 — Creating Spark Applications with KSO | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/creating_distributed_data_processing_applications_with_the_kubeflow_spark_operator/using-the-ks-operator_data-processing |
| RHOAI Supported Configurations 3.x | https://access.redhat.com/articles/rhoai-supported-configs-3.x |
| Kueue — Run a SparkApplication | https://kueue.sigs.k8s.io/docs/tasks/run/kubeflow/sparkapplications/ |
| Kueue — All-or-nothing Scheduling | https://kueue.sigs.k8s.io/docs/concepts/all_or_nothing/ |
| Kueue — waitForPodsReady setup | https://kueue.sigs.k8s.io/docs/tasks/manage/setup_wait_for_pods_ready/ |
| Kueue — SparkApplication integration PR | https://github.com/kubernetes-sigs/kueue/pull/7268 |
| Kueue — PodsReady executor fix | https://github.com/kubernetes-sigs/kueue/pull/11676 |
| Kueue — integrations.frameworks gotcha | https://github.com/kubernetes-sigs/kueue/issues/10483 |
| Kubeflow Spark Operator — ScheduledSparkApplication | https://spark.kubeflow.org/en/latest/user-guide/running-sparkapplication-on-schedule.html |
