# 01 — Cluster prerequisites

Required before `oc apply -k platform/gitops/bootstrap/`.

## Cluster

- OpenShift 4.18+ with `cluster-admin`
- `oc` logged in
- `kubeseal` installed locally

## Operators (installed by bootstrap)

Bootstrap applies:

- OpenShift GitOps (ArgoCD)
- Sealed Secrets controller
- Agent Sandbox CRD (OpenShell)
- DataScienceCluster / dashboard patches for OGX, MLflow, TrustyAI, Pipelines, AutoRAG

Wait until those operators report healthy before sealing secrets.

## OpenShell client TLS

Every Sandbox mounts `secret/openshell-client-tls`. Ops agents have SealedSecrets for this under `platform/gitops/secrets/*-openshell-tls.yaml`. After OpenShell is running, copy the cluster-issued client cert into a SealedSecret for any new agent namespace, or reuse the controller-generated secret if your OpenShell install creates it per namespace.

## Privileged SCC (do not remove)

Each agent ServiceAccount `openshell-sandbox` is bound to `system:openshift:scc:privileged`. That is an OpenShell sandbox requirement: the supervisor and agent container need `SYS_ADMIN`, `NET_ADMIN`, `SYS_PTRACE`, and `runAsUser: 0` as declared on the Sandbox pod template. Do not replace this with a restricted SCC unless OpenShell documents a supported alternative.

Protected namespaces (`openshift-*`, `kube-*`, `redhat-ods-*`) stay a **soul/skill** rule, not an SCC change.
