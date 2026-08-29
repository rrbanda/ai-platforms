# Design Decisions

Architecture decisions made during the build of this RHOAI GitOps deployment.

---

## Why Helm chart + GitOps

The official Red Hat RHOAI Helm chart is extracted from the OCI registry
(`oci://registry.redhat.io/rhai/rhai-on-openshift-chart`) and committed to
Git. ArgoCD reads the chart directly from the repo -- no OCI registry
authentication is needed at deploy time. The chart is unmodified; all
customization is in Helm values passed via the ArgoCD Application manifest.

## Why branch-per-version

Each RHOAI release gets its own branch (`helm-deploy-v3.5`, `helm-deploy-v3.4`).
This isolates the chart version, DSC configuration, and workload manifests per
release. Upgrading is changing `targetRevision` in the app-of-apps. Rolling
back is changing it back. Both versions can coexist in the same repo.

## Why app-of-apps with sync waves

ArgoCD discovers child Applications in `deploy/applications/` and deploys them
in wave order. This ensures operators are ready before the platform, and the
platform is ready before workloads:

- **Wave 0**: Prerequisite operators (Service Mesh 3.x, MCP Gateway)
- **Wave 1**: RHOAI platform (Helm chart DSC) + cluster config
- **Wave 2**: Application workloads (AutoRAG)

## Why deploy/ + setup/ separation

Resources in `deploy/` are continuously managed by ArgoCD -- they represent
the desired state of the cluster. Resources in `setup/` are applied once
during initial bootstrap (GitOps operator, SealedSecrets operator, RHACM
registration) and are never reconciled by ArgoCD. Mixing them creates
confusion about what ArgoCD controls.

## Why numbered directories (00-, 01-, 02-, 03-)

The directory listing naturally shows deployment order. `ls deploy/` reads as
a deployment sequence: operators first, platform second, config third,
workloads last. This matches the sync wave numbers in the Application manifests.

## Why deploy/ serves as both hub deployment and spoke template

The same `deploy/` paths are referenced by:
1. The hub's own `deploy/app-of-apps.yaml` (hub deploys itself)
2. The `clusters/hubs/primary/applicationsets/` (spokes pull the same paths)

This avoids duplicating manifests. A change to `deploy/02-config/` applies to
both the hub and all spokes on next sync.

## Why Pull Model for hub-spoke (not Push)

Push Model requires the hub ArgoCD to hold credentials for every spoke cluster
and reconcile all resources centrally. This doesn't scale beyond ~10 clusters.
Pull Model uses RHACM's `ManifestWork` API to deliver ArgoCD Application
resources to spokes, where each spoke's local ArgoCD pulls from Git and
reconciles independently. The hub only manages Placements and ApplicationSets.

## Why label-driven capability selection

ManagedCluster labels (`rhoai.io/platform`, `rhoai.io/gpu`, `rhoai.io/rag`,
`rhoai.io/training`) drive what each spoke receives. Adding a capability is
`oc label managedcluster <name> rhoai.io/rag=true`. Removing it is removing
the label. No Git changes needed for per-cluster decisions.

## Why SealedSecrets

Encrypted secrets are safe to commit to Git. Each cluster has a unique Sealed
Secrets controller with its own key pair, so a secret encrypted for cluster A
cannot be decrypted on cluster B. Plaintext templates live in
`secrets/templates/` (gitignored) and are never committed.

## Why Kueue is Unmanaged (not Managed)

The RHOAI 3.5 v2 DSC API webhook rejects `kueue.managementState: Managed`.
The Helm chart installs the Kueue operator via its own OLM Subscription.
`Unmanaged` tells the RHOAI operator to integrate with Kueue but not control
its lifecycle -- and it unlocks the `autoCreateQueues`,
`defaultClusterQueueName`, `defaultLocalQueueName` fields that `Managed` ignores.

## Why OdhDashboardConfig is in 02-config (not in the Helm chart)

The dashboard feature flags (`genAiStudio`, `mcpCatalog`, `agentsCatalog`, etc.)
are a cluster-wide singleton that defaults all flags to `false`. The Helm chart
deploys the backend operators but does not flip these toggles. Managing them
separately in `02-config/` allows changing UI features without re-rendering the
entire Helm chart.

## Why multi-hub support

`clusters/hubs/primary/` and `clusters/hubs/dr/` allow independent spoke
management per hub. Each hub has its own Placements (targeting different
ManagedClusters) and its own Policies. A DR hub can manage a separate fleet
or take over the primary's spokes by adjusting labels.

## Why the default AppProject is locked down

The ArgoCD docs recommend: "lock down the default AppProject so no one can use
it by mistake." Our `default` project only allows Applications in the
`openshift-gitops` namespace targeting the same repo. This prevents accidental
deployments to unrestricted destinations. Only the app-of-apps parent uses
`default`; all child apps use purpose-specific projects.

## Why resource exclusions include Leases, Events, EndpointSlices

ArgoCD v3.0 ships default exclusions for high-churn objects. We exclude
`coordination.k8s.io/Lease`, `events.k8s.io/Event`, core `Event`,
`discovery.k8s.io/EndpointSlice`, and `metrics.k8s.io/*` to reduce API server
load and unnecessary ArgoCD reconciliation cycles.

## Why custom health checks for every RHOAI CRD

Without Lua health checks, ArgoCD shows blank health for custom resources. We
provide health checks for: DSC, DSCI, InferenceService, Subscription,
OGXServer, EvalHub, MLflow, NemoGuardrails, and DSPA. This gives accurate
Healthy/Progressing/Degraded status in the ArgoCD UI.

## Why ignoreDifferences for operator-managed annotations

The RHOAI operator adds `platform.opendatahub.io/instance.*` annotations to
resources it manages. These cause false OutOfSync in ArgoCD because they're
not in Git. We ignore them at the system level to prevent unnecessary diffs.

## Why notifications scaffolding

The `NotificationsConfiguration` CR provides webhook-based alerting for sync
failures and health degradation. It ships disabled (the admin provides a
webhook URL). This follows the OpenShift GitOps 1.20+ `NotificationsConfiguration`
API rather than directly editing `argocd-notifications-cm`.

## Why progressive rollout for spoke ApplicationSets

At fleet scale (20+ clusters), a bad config change could affect all spokes
simultaneously. The `RollingSync` strategy updates canary spokes (labeled
`rhoai.io/canary: "true"`) first, then rolls out to the fleet only if canaries
are healthy. This is Technology Preview in GitOps 1.21 but is the documented
pattern for fleet safety.
