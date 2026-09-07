---
name: feature-store-setup
description: "Deploy and configure Feast Feature Store for ML feature management, materialization, and online/offline serving."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Feast, Feature Store, Materialization, Online Store, Offline Store]
---

# Feature Store Setup

Deploy and configure Feast Feature Store on OpenShift AI using the Feast Operator. This skill covers creating FeatureStore CRs, configuring online/offline stores and registries, setting up materialization jobs, and monitoring feature freshness.

## Trigger Conditions

- "Set up a feature store"
- "Deploy Feast on OpenShift AI"
- "Configure online and offline feature stores"
- "Set up feature materialization"
- "Create a FeatureStore custom resource"
- "How do I manage ML features in RHOAI?"
- "Configure Redis as the online store for Feast"
- "Set up feature freshness monitoring"
- "Materialize features from offline to online store"
- "Check feature store health"

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| mcp_rhoai | `cluster_summary` | Verify Feast Operator is enabled in the DSC |
| mcp_rhoai | `explore_cluster` | Discover existing FeatureStore deployments |
| mcp_openshift | `resources_list` | List FeatureStore CRs, Pods, CronJobs, Secrets |
| mcp_openshift | `resources_get` | Inspect individual FeatureStore CR status |
| mcp_openshift | `pods_list` | Check Feast server pod health |
| mcp_openshift | `events_list` | Diagnose deployment or scheduling failures |

## Procedure

### Phase 1: Verify Feast Operator Readiness

1. Call `mcp_rhoai_cluster_summary` to confirm the Feast Operator component is enabled:
   ```bash
   oc get dsc default-dsc -o jsonpath='{.spec.components.feastoperator.managementState}'
   # Expected: Managed
   ```

2. Verify the Feast Operator pod is running:
   ```bash
   oc get pods -n redhat-ods-applications -l app.kubernetes.io/name=feast-operator --no-headers
   ```

3. Confirm the FeatureStore CRD is installed:
   ```bash
   oc get crd featurestores.feast.dev
   ```

### Phase 2: Plan Feature Store Architecture

4. Determine the store topology based on user requirements:

| Component | Options | Use Case |
|-----------|---------|----------|
| **Online Store** | Redis, SQLite (default) | Low-latency feature serving for inference |
| **Offline Store** | File-based (default), BigQuery, Snowflake, PostgreSQL | Historical feature retrieval for training |
| **Registry** | SQLite (default), PostgreSQL, S3-backed | Feature definition metadata storage |

5. Identify required credentials:
   - Redis: connection URL and password
   - BigQuery/Snowflake: service account credentials
   - PostgreSQL: connection string
   - S3: access key, secret key, endpoint, bucket

### Phase 3: Create the FeatureStore CR

6. Create the target namespace if it doesn't exist:
   ```bash
   oc new-project {feature-store-namespace}
   ```

7. Create any required secrets before the FeatureStore CR.

**Redis credentials (if using Redis online store):**
```bash
oc create secret generic feast-redis-secret \
  -n {namespace} \
  --from-literal=REDIS_URL="redis://:{password}@{redis-host}:6379/0"
```

**PostgreSQL credentials (if using PostgreSQL registry):**
```bash
oc create secret generic feast-registry-secret \
  -n {namespace} \
  --from-literal=REGISTRY_URL="postgresql://{user}:{password}@{host}:5432/{db}"
```

8. Generate the FeatureStore CR based on the chosen topology.

**Basic FeatureStore (SQLite online + file offline — development):**

```yaml
apiVersion: feast.dev/v1alpha1
kind: FeatureStore
metadata:
  name: {name}
  namespace: {namespace}
spec:
  feastProject: {project-name}
  services:
    onlineStore:
      persistence:
        store:
          type: sqlite
    offlineStore:
      persistence:
        store:
          type: file
    registry:
      local:
        persistence:
          store:
            type: sqlite
```

**Production FeatureStore (Redis online + PostgreSQL registry):**

```yaml
apiVersion: feast.dev/v1alpha1
kind: FeatureStore
metadata:
  name: {name}
  namespace: {namespace}
spec:
  feastProject: {project-name}
  services:
    onlineStore:
      persistence:
        store:
          type: redis
          secretRef:
            name: feast-redis-secret
      resources:
        requests:
          cpu: 500m
          memory: 512Mi
        limits:
          cpu: "2"
          memory: 2Gi
      replicas: 2
    offlineStore:
      persistence:
        store:
          type: file
      resources:
        requests:
          cpu: 250m
          memory: 256Mi
        limits:
          cpu: "1"
          memory: 1Gi
    registry:
      local:
        persistence:
          store:
            type: postgresql
            secretRef:
              name: feast-registry-secret
```

9. Apply the FeatureStore CR:
   ```bash
   oc apply -f featurestore.yaml
   ```

10. Wait for the Feast Operator to reconcile and deploy all components:
    ```bash
    oc wait featurestore {name} -n {namespace} --for=condition=Ready --timeout=300s
    ```

11. Verify all Feast pods are running:
    ```bash
    oc get pods -n {namespace} -l app.kubernetes.io/managed-by=feast-operator --no-headers
    ```

### Phase 4: Register Feature Definitions

12. Access the Feast CLI from within a workbench or a pod with `feast` installed:

    ```bash
    feast init {project-name}
    cd {project-name}
    ```

13. Define feature views in `feature_repo/feature_definitions.py`:

    ```python
    from feast import Entity, FeatureView, Field, FileSource
    from feast.types import Float32, Int64

    customer = Entity(name="customer_id", join_keys=["customer_id"])

    customer_features = FeatureView(
        name="customer_features",
        entities=[customer],
        schema=[
            Field(name="total_purchases", dtype=Int64),
            Field(name="avg_order_value", dtype=Float32),
            Field(name="days_since_last_order", dtype=Int64),
        ],
        source=FileSource(
            path="data/customer_features.parquet",
            timestamp_field="event_timestamp",
        ),
        ttl=timedelta(days=1),
    )
    ```

14. Plan and apply the feature definitions:
    ```bash
    feast plan
    feast apply
    ```

### Phase 5: Configure Materialization

15. Run an initial materialization to populate the online store:
    ```bash
    feast materialize-incremental $(date -u +"%Y-%m-%dT%H:%M:%S")
    ```

16. Create a CronJob for scheduled materialization:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: feast-materialize-{project-name}
  namespace: {namespace}
spec:
  schedule: "0 */6 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: feast-materialize
              image: quay.io/opendatahub/feast:latest
              command:
                - feast
                - materialize-incremental
                - $(date -u +"%Y-%m-%dT%H:%M:%S")
              env:
                - name: FEAST_REPO_PATH
                  value: /feature_repo
              volumeMounts:
                - name: feature-repo
                  mountPath: /feature_repo
              resources:
                requests:
                  cpu: 250m
                  memory: 512Mi
                limits:
                  cpu: "1"
                  memory: 2Gi
          restartPolicy: OnFailure
          volumes:
            - name: feature-repo
              persistentVolumeClaim:
                claimName: feast-repo-pvc
```

17. Apply the CronJob:
    ```bash
    oc apply -f feast-materialize-cronjob.yaml
    ```

### Phase 6: Set Up Monitoring

18. Verify Prometheus is scraping Feast metrics:
    ```bash
    oc get servicemonitor -n {namespace} -l app.kubernetes.io/managed-by=feast-operator
    ```

19. Key Feast metrics to monitor:

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `feast_feature_server_request_latency_seconds` | Feature retrieval latency | p99 > 100ms |
| `feast_feature_server_request_count` | Request throughput | Sudden drop |
| `feast_materialization_job_duration_seconds` | Materialization job runtime | > 2x baseline |
| `feast_feature_freshness_seconds` | Time since last materialization | > TTL of feature view |

20. Check feature freshness:
    ```bash
    feast feature-views list
    ```

### Phase 7: Generate GitOps Manifests

21. Output all resources as GitOps-compatible YAML:
    - FeatureStore CR
    - Secrets (with placeholder values — actual credentials in SealedSecrets or ExternalSecrets)
    - Materialization CronJob
    - ServiceMonitor (if custom)
    - Place under the appropriate Kustomize overlay directory

## Output Format

```
# Feature Store Deployment Report — {timestamp}

## Feast Operator Status
- Management State: Managed ✓
- Operator Pod: Running ✓
- CRD Installed: ✓

## FeatureStore: {name}
- Namespace: {namespace}
- Project: {project-name}
- Status: Ready ✓

## Store Configuration
| Component | Type | Backend | Replicas | Status |
|-----------|------|---------|----------|--------|
| Online Store | {type} | {backend} | {n} | Running |
| Offline Store | {type} | {backend} | {n} | Running |
| Registry | {type} | {backend} | {n} | Running |

## Pods
| Pod | Status | Restarts | Age |
|-----|--------|----------|-----|
| {pod-name} | Running | 0 | {age} |

## Materialization
- Schedule: {cron expression}
- Last Run: {timestamp}
- Next Run: {timestamp}
- Status: {Success/Failed}

## Feature Views
| Name | Entities | Features | TTL | Last Materialized |
|------|----------|----------|-----|-------------------|
| {name} | {entities} | {count} | {ttl} | {timestamp} |

## GitOps Manifests
{YAML for ArgoCD deployment}
```

## Safety Constraints

- Never store database credentials or Redis passwords directly in the FeatureStore CR — always use Kubernetes Secrets referenced via `secretRef`
- Before deleting a FeatureStore CR, verify no inference pipelines depend on the online store for real-time features — deletion removes all deployed Feast components
- Materialization CronJobs write to the online store — ensure they do not overlap (set `concurrencyPolicy: Forbid` on the CronJob)
- Do not set materialization frequency higher than the data update frequency of the offline source — this wastes compute without improving freshness
- The Feast Operator manages pod lifecycle — do not manually scale or delete Feast pods; modify the FeatureStore CR instead
- Registry migrations (e.g., SQLite to PostgreSQL) require a `feast apply` with the new registry backend — coordinate with data science teams to avoid feature definition conflicts
- All changes must go through Git (PR) — never apply FeatureStore CRs directly with `oc apply` in production

## Disconnected Environment Notes

- The Feast Operator image and feature server images must be mirrored to the internal registry; update the FeatureStore CR's `image` field if using a non-default registry
- File-based offline store is the most suitable option for disconnected environments — it requires no external data warehouse connectivity
- SQLite-based online store and registry require no external services and work fully offline, suitable for development and small-scale production
- If using Redis as the online store, it must be deployed within the cluster — external Redis endpoints are unreachable in air-gapped environments
- The `feast` CLI must be available in a mirrored container image or pre-installed in the workbench notebook image
- Materialization CronJob images must be pre-pulled or available from the internal registry
- Prometheus monitoring works with the in-cluster monitoring stack — no external endpoints required
