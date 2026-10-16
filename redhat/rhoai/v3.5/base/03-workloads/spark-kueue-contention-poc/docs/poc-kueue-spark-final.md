# POC: Kueue + Spark Operator on RHOAI 3.5 — Resource-Contention Protection

## 1. Background

The team currently runs Spark batch workloads on OpenShift. This POC validates two platform capabilities that RHOAI 3.5 makes available:

1. **Kubeflow Spark Operator (KSO)** — declarative, Kubernetes-native submission and lifecycle management of Spark jobs via `SparkApplication` / `ScheduledSparkApplication` CRDs, replacing ad-hoc `spark-submit` scripts and client-mode submission.

2. **Kueue** — quota-based admission control and gang scheduling for batch workloads sharing a common OpenShift resource pool.

A concrete, business-relevant risk scenario was identified and we would like to validate it in a controlled POC environment before recommending broader adoption.

**Environment ask:** Pre-staged setup in eLab (interim), transitioning to iLab once app-team access is provisioned.

---

## 2. Problem Statement

**Observed/anticipated failure mode:** A Spark job is submitted requesting more aggregate resources (e.g., 10 CPU across driver + executors) than are currently available in the cluster (e.g., only 2 CPU free). Today, without any admission-control layer:

- The Spark Operator creates the Driver and Executor pods **without any upfront capacity check**.
- The `kube-scheduler` schedules pods **independently, one at a time** — the Driver (small footprint) and a subset of Executors that fit start Running, while the remaining Executors are left in Pending.
- The job becomes **"half-admitted"** — partially running, partially stuck — and the Driver waits indefinitely (or until a timeout) for the missing Executors.
- If `restartPolicy` is configured to retry on failure, this escalates into a **retry loop**, repeatedly creating and tearing down pods, compounding the resource waste.
- Compute resources (CPU/memory) are **held and effectively wasted** for the duration of the stuck/retrying job, reducing capacity for other tenants.

**Why this matters:** As more Spark batch workloads consolidate onto a shared OpenShift cluster (multi-tenant model), the probability of concurrent job submissions exceeding available capacity increases. Without admission control, a single oversized or mistimed submission degrades the experience for all workloads sharing the same namespace — an operationally expensive and hard-to-diagnose failure mode.

**Evidence:** A read-only investigation identified a historical cluster of three `deposits-*` batch Jobs that failed within roughly 90 minutes of each other (`status.failed=1, succeeded=0`), consistent with a resource-contention pattern. Full root-cause confirmation was not possible because Kubernetes Events (1-hour TTL) had expired and long-retention monitoring was not available. These are treated as a **representative example** — not confirmed root cause — and the POC uses similar resource specifications.

---

## 3. Proposed Solution

Use **Kueue** as an admission-control layer in front of the Spark Operator. When a `SparkApplication` carries a `kueue.x-k8s.io/queue-name` label:

1. Kueue's webhook intercepts the creation and sets `spec.suspend: true`
2. Kueue creates a `Workload` object representing the total resource demand (driver + all executors)
3. Kueue evaluates the `Workload` against the `ClusterQueue` quota
4. If insufficient quota → job stays **Suspended**, zero pods are created, zero resources wasted
5. When quota becomes available → Kueue unsuspends, Spark Operator creates pods
6. On completion, quota is reclaimed automatically for the next queued job

With **gang scheduling enabled** (disabled by default), Kueue additionally evicts and retries jobs whose pods fail to become Ready after admission — a safety net against partial scheduling.

---

## 4. Component Support Matrix (RHOAI 3.5)

| Component | RHOAI 3.5 Status | Version | Source |
|---|---|---|---|
| Kubeflow Spark Operator | **GA** | 2.4.0 | [Supported Configs](https://access.redhat.com/articles/rhoai-supported-configs-3.x) |
| Apache Spark | **GA** | 4.0.1 | Bundled with KSO |
| Red Hat build of Kueue Operator | **GA** | — | [OCP 4.22 AI Workloads](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/ai_workloads/red-hat-build-of-kueue) |
| Kueue + SparkApplication integration | **Technology Preview** | — | [RHOAI 3.5 TP features](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/release_notes/technology-preview-features_relnotes) |
| ScheduledSparkApplication | **Not explicitly documented** | — | CRD ships with KSO; functional but not called out in RHOAI 3.5 release notes |
| Gang scheduling in Kueue | **Supported (but disabled by default)** | — | [Red Hat Kueue docs, Section 2.15](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/ai_workloads/red-hat-build-of-kueue) |

---

## 5. Test Cases

### Phase 1 — Spark Operator: Production-Readiness Baseline

Confirm that migrating from script-based `spark-submit` to the declarative `SparkApplication` CRD works as expected:

- Declarative submission (`oc apply -f sparkapplication.yaml`) creates Driver + Executor pods and completes a batch job
- Spark History Server captures event logs for post-run analysis
- Pod-level metrics exportable to Prometheus/Grafana
- `restartPolicy` behavior observed and documented when a Driver pod fails

### Phase 2 — Kueue: Admission Control & Resource-Contention Protection

| Test Case | Setup | Expected Result (with Kueue) | Baseline (without Kueue) |
|---|---|---|---|
| **TC-1: Baseline reproduction** | Submit SparkApplication requesting 10 CPU into a namespace with only 4 CPU available, **without** Kueue | N/A (baseline) | Driver runs; executors Pending; job hangs; resources wasted |
| **TC-2: Kueue admission blocking** | Same job with `kueue.x-k8s.io/queue-name` label, insufficient ClusterQueue quota | SparkApplication stays **Suspended**; zero pods created | — |
| **TC-3: Gang scheduling** | Quota short by exactly one Executor's resources | Kueue does **not** partially admit; job queued until full resource set available | — |
| **TC-4: Quota release & re-admission** | Run a large job consuming quota; queue a second job behind it | First job completes → quota released → second job auto-admitted; measure queue wait time | — |
| **TC-5: Dynamic Allocation** | SparkApplication with `dynamicAllocation.enabled=true` under Kueue | **Rejected by Kueue webhook** — executor count must be fixed | — |
| **TC-6: Retry behavior comparison** | `restartPolicy: OnFailure` with and without Kueue under contention | With Kueue: zero pod churn (job stays Suspended). Without: repeated pod create/fail cycles | Retry storm |

### Success Criteria

- **TC-2 and TC-3** demonstrate that Kueue prevents the "partially-scheduled, resource-wasting" state — the primary validation goal
- **TC-4** produces a measurable, acceptable queue-wait time for production planning
- **TC-5 and TC-6** produce documented constraints/behaviors for the production rollout decision

---

## 6. What We Confirmed from Red Hat Docs

| Claim | Status | Red Hat Source |
|---|---|---|
| Kueue supports gang scheduling / all-or-nothing | ✅ **Confirmed** | OCP 4.22 Kueue docs, Section 2.15: *"Red Hat build of Kueue enables gang scheduling by suspending jobs until the cluster can guarantee capacity to start and execute all related jobs together."* |
| Gang scheduling is **disabled by default** | ✅ **Confirmed** | Requires `gangScheduling.policy: ByWorkload` in the Kueue CR. Default is `None`. |
| Kueue CR API is `kueue.openshift.io/v1` | ✅ **Confirmed** | All examples in Red Hat docs use this API version |
| ClusterQueue/LocalQueue/ResourceFlavor use `kueue.x-k8s.io/v1beta2` | ✅ **Confirmed** | `v1beta1` is deprecated per Red Hat docs |
| Namespace must be labeled `kueue.openshift.io/managed=true` | ✅ **Confirmed** | Both Red Hat Kueue + RHOAI docs |
| `kueue.x-k8s.io/queue-name` label triggers Kueue management | ✅ **Confirmed** | Both Red Hat Kueue + RHOAI docs |
| Spark Operator is GA in RHOAI 3.5 (v2.4.0) | ✅ **Confirmed** | Supported Configurations page |
| Kueue + SparkApplication is Technology Preview | ✅ **Confirmed** | RHOAI 3.5 release notes TP section |
| Dynamic Allocation not supported with Kueue | ✅ **Confirmed** | Upstream Kueue docs + webhook source code |

---

## 7. What We Could NOT Confirm from Red Hat Docs (Documentation Gaps)

These are items where the upstream (community) Kueue docs describe one configuration path, but the Red Hat docs are silent or inconsistent. **These need engineer clarification.**

| Gap | Detail | Risk |
|---|---|---|
| **How to enable SparkApplication in Kueue** | RHOAI 3.5 release notes say Kueue+Spark is TP, but provide **zero configuration steps**. The RHOAI Spark Operator docs don't mention Kueue. The Red Hat Kueue docs don't mention SparkApplication. | We don't know the exact steps to enable this on a Red Hat cluster. Upstream requires a `SparkApplicationIntegration` feature gate + adding to `integrations.frameworks`, but the Red Hat Kueue CR (`kueue.openshift.io/v1`) does not expose a `featureGates` field. |
| **SparkApplication not in supported frameworks** | Red Hat Kueue docs list supported `integrations.frameworks` as: `BatchJob`, `Pod`, `Deployment`, `StatefulSet`, `LeaderWorkerSet`, `JobSet`. SparkApplication is **absent**. | Unclear if you just add `sparkoperator.k8s.io/sparkapplication` to the list, or if RHOAI auto-configures it when the Spark Operator is `Managed`. |
| **`waitForPodsReady` configuration** | RHOAI docs mention it in a troubleshooting tip and link to upstream docs, but Red Hat Kueue docs (OCP 4.22) don't document it at all. | Unclear if the Red Hat Kueue CR exposes this field or if it must be configured differently. |
| **`PodsReady` executor bug** | Upstream Kueue had a bug where `PodsReady` only checked driver state, leaving stuck executors undetected ([#11675](https://github.com/kubernetes-sigs/kueue/issues/11675), fixed in [#11676](https://github.com/kubernetes-sigs/kueue/pull/11676)). | Unknown if the Red Hat build of Kueue includes this fix. Critical for gang scheduling with SparkApplication. |
| **ScheduledSparkApplication support** | RHOAI 3.5 says "Native Cron support for running scheduled applications" but ScheduledSparkApplication is not called out as GA or TP in the release notes. | Unclear if this is officially supported or just functional. |
| **Kueue + ScheduledSparkApplication interaction** | Each ScheduledSparkApplication creates child SparkApplication objects on a cron schedule. If those children carry the Kueue label (via the template), Kueue should manage them. | Completely untested and undocumented in RHOAI scope. |

---

## 8. Questions for the Engineering Team

### SparkApplication + Kueue Enablement

1. **How exactly is SparkApplication support enabled in the Red Hat build of Kueue on RHOAI 3.5?** The upstream Kueue requires a `SparkApplicationIntegration` feature gate + adding `sparkoperator.k8s.io/sparkapplication` to `integrations.frameworks`. Does RHOAI auto-configure this when Spark Operator is `Managed` in the DataScienceCluster, or is there a manual step?

2. **Does the Red Hat Kueue CR (`kueue.openshift.io/v1`) expose a `featureGates` field?** The upstream Kueue has one, but it's not shown in any Red Hat doc examples. If not, how are alpha/TP integrations like SparkApplication toggled?

3. **Can you share the exact Kueue CR configuration that enables SparkApplication admission?** We have ready-to-apply YAMLs for the test cases but need the correct Kueue CR snippet to complete the setup.

### Gang Scheduling

4. **Is `gangScheduling.policy: ByWorkload` required for the TC-3 (all-or-nothing) test case, or does the default quota reservation already prevent partial admission for SparkApplications?** The Red Hat docs describe two layers: quota-level all-or-nothing (always on) and gang scheduling (opt-in). We need to confirm which layer is sufficient for our use case.

5. **When gang scheduling is enabled with `admission: Sequential`, what is the default timeout before a job is evicted and retried?** Is this configurable in the Red Hat Kueue CR?

### Known Issues

6. **Does the Red Hat build of Kueue include the fix for [#11675](https://github.com/kubernetes-sigs/kueue/issues/11675) (`PodsReady` only checking driver state)?** Without this fix, `waitForPodsReady` / gang scheduling won't detect stuck executors, and the workload will sit indefinitely with the driver running and zero executors ready.

7. **Is `waitForPodsReady` configurable in the Red Hat Kueue CR?** The RHOAI docs reference it in troubleshooting but the Red Hat Kueue docs don't document it. If it's available, what is the correct field path?

### ScheduledSparkApplication

8. **Is `ScheduledSparkApplication` officially supported in RHOAI 3.5?** It is functional (CRD is installed, we've tested it), but not called out in the release notes as GA or TP. Can we rely on it for production batch scheduling, or should we use a CronJob wrapper instead?

9. **If a ScheduledSparkApplication template includes the `kueue.x-k8s.io/queue-name` label, will Kueue manage each child SparkApplication it creates?** Has this interaction been tested?

### Support Exception

10. **Given that Kueue + SparkApplication is Technology Preview, what is the process for obtaining a support exception for production use?** We understand TP features have no production SLA. If the POC validates successfully, we'd like to move forward with a support exception while waiting for GA.

---

## 9. Proposed Reference Configuration

We request the OpenShift Engineering team to stand up the following in the eLab environment:

- **Base workload pattern:** a representative PySpark batch job (driver + 1–2 executors, similar resource shape to `deposits-*` production jobs)

- **Three submission variants:**
  1. `SparkApplication` — single run (GA)
  2. `SparkApplication` + `kueue.x-k8s.io/queue-name` label — Kueue-managed (TP)
  3. `ScheduledSparkApplication` — cron-based recurring run (pending support confirmation)

- **Supporting infrastructure:**
  - `ClusterQueue` with deliberately constrained CPU quota (to reproduce contention on demand)
  - `LocalQueue` in the target namespace
  - Spark History Server for post-run observability
  - Gang scheduling enabled in Kueue CR (`gangScheduling.policy: ByWorkload`)

- **Prerequisites on the OpenShift side:**
  - Spark Operator webhook `namespaceSelector` patched to include the target namespace
  - `NetworkPolicy` permitting Driver↔Executor communication (ports 7078/7079/4040)
  - Namespace labeled `kueue.openshift.io/managed=true`

**We have ready-to-apply YAML manifests** for all of the above (SparkApplication variants, ClusterQueue/LocalQueue, NetworkPolicy, and test cases TC-1 through TC-6) and can supply them to accelerate setup.

---

## 10. Deliverable

A walkthrough/demo session covering:

1. **Live reproduction:** TC-1 (the problem) vs. TC-2/TC-3 (Kueue's mitigation) side by side
2. **Queue wait time:** Observed quota reclamation behavior (TC-4) with timing measurements
3. **Constraints document:** Dynamic Allocation limitation (TC-5), retry behavior (TC-6), and support-level caveats so an informed production-adoption recommendation can be made to leadership

---

## 11. Reference Links

| Resource | URL |
|---|---|
| RHOAI 3.5 Release Notes — TP Features | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/release_notes/technology-preview-features_relnotes |
| RHOAI 3.5 — Manage workloads with Kueue | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/managing_openshift_ai/managing-workloads-with-kueue |
| RHOAI 3.5 — Spark Operator user guide | https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/creating_distributed_data_processing_applications_with_the_kubeflow_spark_operator/using-the-ks-operator_data-processing |
| RHOAI Supported Configurations 3.x | https://access.redhat.com/articles/rhoai-supported-configs-3.x |
| Red Hat build of Kueue (OCP 4.22) | https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/ai_workloads/red-hat-build-of-kueue |
| Kueue upstream — Run a SparkApplication | https://kueue.sigs.k8s.io/docs/tasks/run/kubeflow/sparkapplications/ |
| Kueue upstream — All-or-nothing scheduling | https://kueue.sigs.k8s.io/docs/concepts/all_or_nothing/ |
| Kueue upstream — PodsReady executor fix | https://github.com/kubernetes-sigs/kueue/pull/11676 |
