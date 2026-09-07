# 11 — Live Cluster Test Results

> Results from testing rhoai-copilot against a real OpenShift cluster.
> Last updated: 2026-08-22

---

## Cluster Details

| Field | Value |
|-------|-------|
| Platform | ROSA |
| OCP Version | 4.21.28 (reported, provisioned as 4.21.5) |
| API | `<CLUSTER_API_URL>` |
| Region | us-east-2 |
| Type | Connected (not air-gapped) |
| OpenShell | Installed (agent-sandbox-system, openshell namespaces) |

---

## Test 1: Uninstall RHOAI (2026-08-22)

### Pre-uninstall State

| Component | State |
|-----------|-------|
| RHOAI version | 3.4.0 (rhods-operator.3.4.0) |
| ServiceMesh | 3.2.0 (servicemeshoperator3.v3.2.0) |
| cert-manager | Not installed (no subscription) |
| NFD | Not installed |
| GPU operator | Not installed |
| ArgoCD/GitOps | Not installed |
| DSCInitialization | Ready (phase=Ready, 155 days old) |
| DataScienceCluster | **NOT Ready** (reason: "Some components are not ready: trainer") |
| RHOAI pods | 15 pods in redhat-ods-applications |
| Operator pods | 3 pods in redhat-ods-operator |

### Key Finding: `trainer` Trap Confirmed on Live Cluster

The DSC was NotReady because `trainer` component defaulted to Managed (requiring JobSet operator which wasn't installed). This is EXACTLY the v1 API trap our v2 skill documentation warns about. Live validation of the bug.

### Uninstall Steps Executed

| Step | Command | Result | Duration |
|------|---------|--------|----------|
| 1 | `oc delete datasciencecluster --all` | Deleted `default-dsc` | ~1s |
| 1b | Wait for pods to drain | 2 pods remaining after 10s | 10s |
| 2 | `oc delete dscinitialization --all` | Deleted `default-dsci` | ~1s |
| 3 | Delete RHOAI Subscription + CSV + OG | All deleted | ~2s |
| 4 | Delete ServiceMesh 3 Subscription + CSV | All deleted | ~1s |
| 5 | Delete namespaces (5 namespaces) | All deleted | ~37s |

### Post-uninstall Verification

| Check | Result |
|-------|--------|
| RHOAI CSVs | CLEAN (0) |
| RHOAI Subscriptions | CLEAN (0) |
| ServiceMesh CSVs | CLEAN (0, OLM cleaned up copies) |
| DataScienceCluster resources | CLEAN (0) |
| DSCInitialization resources | CLEAN (0) |
| RHOAI namespaces | CLEAN (0) |
| RHOAI-related pods | CLEAN (0) |
| RHOAI CRDs | 38 still registered (normal -- CRDs persist after operator removal) |
| ImagePullBackOff pods | Not checked (jq parse issue, cluster otherwise clean) |

### Verdict: UNINSTALL SUCCESSFUL

Clean removal in ~50 seconds total. The rhoai-uninstall skill procedure works correctly on a live cluster.

---

## Cluster 2: OCP 4.20.22

| Field | Value |
|-------|-------|
| API | `<CLUSTER_API_URL>` |
| Console | `<CLUSTER_CONSOLE_URL>` |
| User | `<CLUSTER_ADMIN_USER>` |
| OCP | 4.20.22 |
| RHOAI | 3.5.0-ea.2 (already installed) |
| rhoai-copilot | NOT deployed |
| Build tool | podman available locally |
| Registry | `<REGISTRY_URL>` |

### Pending: Deploy rhoai-copilot Agent

Next steps for a fresh conversation:
1. Build agent image: `podman build -f runtimes/hermes/Containerfile -t <REGISTRY>/rhoai-copilot:latest .`
2. Push: `podman push <REGISTRY>/rhoai-copilot:latest`
3. Create namespace + secrets on cluster
4. Deploy: `oc apply -k .`
5. Deploy RHOAI MCP server
6. Verify agent dashboard accessible
7. Test agent conversation: "Deploy RHOAI on my cluster" / "Uninstall RHOAI"

## Pending Tests

- [ ] Deploy rhoai-copilot agent on cluster 2
- [ ] Test agent conversational flow via dashboard
- [ ] CLI path: install cert-manager → OSSM3 → RHOAI → DSCI → DSC v2, run validator
- [ ] GitOps path: scaffold repo, apply ArgoCD health checks + app-of-apps, monitor sync-waves
