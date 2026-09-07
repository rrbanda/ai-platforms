---
name: maas-subscription-manager
description: "Manage MaaS subscriptions, token quotas, rate limiting, API keys, and usage tracking for Models-as-a-Service governance."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, MaaS, Subscription, API Keys, Rate Limiting, Governance, Kuadrant]
---

# MaaS Subscription Manager

Manage Models-as-a-Service (MaaS) subscriptions, authentication policies, API keys, and usage tracking. Subscriptions control who can access which models, with what token quotas and rate limits, through the MaaS gateway.

## Trigger Conditions

- "Create a MaaS subscription for team X"
- "Set token rate limits on a model subscription"
- "Generate an API key for MaaS"
- "Revoke an API key"
- "List all MaaS subscriptions"
- "Who has access to model Y?"
- "Change rate limits on a subscription"
- "Check MaaS usage for cost attribution"
- "Set up group-based access for MaaS"
- "Export MaaS usage data"
- "Prioritize subscription A over subscription B"

## API Group

All MaaS governance CRs use **`maas.opendatahub.io/v1alpha1`** — not `models.opendatahub.io/v1alpha1`.

## Namespace Reference

| Resource | Namespace |
|----------|-----------|
| MaaSSubscription | `models-as-a-service` |
| MaaSAuthPolicy | `models-as-a-service` |
| MaaSModelRef | Model's own namespace (e.g., `ai-eng-models`) |
| maas-api, maas-postgres | `redhat-ai-gateway-infra` |
| Kuadrant AuthPolicy, Gateway | `openshift-ingress` |

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| mcp_rhoai | `list_inference_services` | Find deployed models available for subscription |
| mcp_rhoai | `get_inference_service` | Get model details and serving status |
| mcp_rhoai | `cluster_summary` | Cluster-wide MaaS deployment overview |
| mcp_openshift | `resources_list` | List MaaSSubscriptions, MaaSAuthPolicies, MaaSModelRefs |
| mcp_openshift | `resources_get` | Inspect individual subscription or policy details |

## Procedure

### Phase 1: Discover Available Models

1. List models published to MaaS:
   ```bash
   oc get maasmodelref -A -o custom-columns=\
   'NAME:.metadata.name,NAMESPACE:.metadata.namespace,MODEL:.spec.modelRef.name,PHASE:.status.phase'
   ```

2. Call `mcp_rhoai_list_inference_services` to get the full set of deployed models and their readiness status.

3. Identify the target model and its namespace for subscription creation.

### Phase 2: List Existing Subscriptions

4. List all subscriptions:
   ```bash
   oc get maassubscription -n models-as-a-service -o custom-columns=\
   'NAME:.metadata.name,MODEL:.spec.modelRef.name,USER:.spec.user,GROUP:.spec.group,RATE-HOUR:.spec.rateLimits.tokensPerHour,PRIORITY:.spec.priority,PHASE:.status.phase'
   ```

5. List all auth policies:
   ```bash
   oc get maasauthpolicy -n models-as-a-service -o custom-columns=\
   'NAME:.metadata.name,MODEL:.spec.modelRef.name,USER:.spec.user,GROUP:.spec.group,PHASE:.status.phase'
   ```

6. Verify the Kuadrant AuthPolicy was auto-created:
   ```bash
   oc get authpolicy -n openshift-ingress
   ```

### Phase 3: Create Subscription and Auth Policy

7. Create a `MaaSSubscription` to grant access with token quotas:

**User-scoped subscription:**

```yaml
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSSubscription
metadata:
  name: {model-name}-{user}-sub
  namespace: models-as-a-service
spec:
  modelRef:
    name: {model-name}
    namespace: {model-namespace}
  user: {openshift-username}
  rateLimits:
    tokensPerHour: 1000000
    tokensPerDay: 10000000
  priority: 10
```

**Group-scoped subscription:**

```yaml
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSSubscription
metadata:
  name: {model-name}-{group}-sub
  namespace: models-as-a-service
spec:
  modelRef:
    name: {model-name}
    namespace: {model-namespace}
  group: {openshift-group-name}
  rateLimits:
    tokensPerHour: 5000000
    tokensPerDay: 50000000
  priority: 10
```

8. Create a matching `MaaSAuthPolicy`:

```yaml
apiVersion: maas.opendatahub.io/v1alpha1
kind: MaaSAuthPolicy
metadata:
  name: {model-name}-{user-or-group}-auth
  namespace: models-as-a-service
spec:
  modelRef:
    name: {model-name}
    namespace: {model-namespace}
  user: {openshift-username}      # or group: {group-name}
```

9. Apply both resources:
   ```bash
   oc apply -f subscription.yaml
   oc apply -f authpolicy.yaml
   ```

10. Verify status:
    ```bash
    oc get maassubscription {name} -n models-as-a-service -o jsonpath='{.status.phase}'
    # Expected: Active

    oc get maasauthpolicy {name} -n models-as-a-service -o jsonpath='{.status.phase}'
    # Expected: Active

    oc get maasmodelref {model-name} -n {model-namespace} -o jsonpath='{.status.phase}'
    # Expected: Ready (transitions from Pending once both sub + auth exist)
    ```

### Phase 4: API Key Management

11. Create an API key using the MaaS gateway REST API:

    ```bash
    OC_TOKEN=$(oc whoami -t)
    MAAS_HOST=$(oc get route maas-default-gateway -n openshift-ingress -o jsonpath='{.spec.host}')
    TLS=$(oc get route maas-default-gateway -n openshift-ingress -o jsonpath='{.spec.tls.termination}' 2>/dev/null)
    MAAS_URL="$([[ -n "$TLS" ]] && echo "https" || echo "http")://${MAAS_HOST}"

    curl -s -X POST \
      -H "Authorization: Bearer $OC_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"name":"{key-name}","expirationDays":30}' \
      "$MAAS_URL/v1/api-keys"
    ```

    The response contains the `key` field (format: `sk-oai-...`) — this is shown only once.

12. List existing API keys:
    ```bash
    curl -s -H "Authorization: Bearer $OC_TOKEN" "$MAAS_URL/v1/api-keys"
    ```

13. Revoke an API key:
    ```bash
    curl -s -X DELETE -H "Authorization: Bearer $OC_TOKEN" "$MAAS_URL/v1/api-keys/{key-id}"
    ```

14. List subscriptions visible to the authenticated user:
    ```bash
    curl -s -H "Authorization: Bearer $OC_TOKEN" "$MAAS_URL/v1/subscriptions"
    ```

### Phase 5: Update Subscriptions

15. Modify rate limits on an existing subscription:
    ```bash
    oc patch maassubscription {name} -n models-as-a-service --type=merge -p '{
      "spec": {
        "rateLimits": {
          "tokensPerHour": 2000000,
          "tokensPerDay": 20000000
        }
      }
    }'
    ```

16. Change priority (higher number wins when a user has multiple subscriptions):
    ```bash
    oc patch maassubscription {name} -n models-as-a-service --type=merge -p '{
      "spec": { "priority": 20 }
    }'
    ```

17. Disable a subscription without deleting:
    ```bash
    oc patch maassubscription {name} -n models-as-a-service --type=merge -p '{
      "spec": { "suspended": true }
    }'
    ```

### Phase 6: Usage Tracking and Cost Attribution

18. Check usage via the observability dashboard (Technology Preview):
    ```bash
    oc get odhdashboardconfig odh-dashboard-config -n redhat-ods-applications \
      -o jsonpath='{.spec.dashboardConfig.observabilityDashboard}'
    # Must be: true
    ```

19. Query usage metrics from the maas-api:
    ```bash
    API_KEY="sk-oai-{your-key}"
    curl -s -H "Authorization: Bearer $API_KEY" "$MAAS_URL/maas-api/v1/usage" | jq .
    ```

20. Export usage data for cost attribution (CSV):
    ```bash
    curl -s -H "Authorization: Bearer $OC_TOKEN" \
      "$MAAS_URL/maas-api/v1/usage/export?format=csv&from={start-date}&to={end-date}" \
      -o usage-report.csv
    ```

### Phase 7: Generate GitOps Manifests

21. Output all MaaS governance resources as GitOps-compatible YAML:
    - MaaSSubscription and MaaSAuthPolicy YAML files
    - Place under the appropriate Kustomize overlay
    - Strip server-side fields

## Output Format

```
# MaaS Subscription Report — {timestamp}

## Available Models
| Model | Namespace | Phase | Runtime |
|-------|-----------|-------|---------|
| {name} | {ns} | Ready/Pending | vLLM/llm-d |

## Subscriptions
| Name | Model | User/Group | Tokens/Hour | Tokens/Day | Priority | Phase |
|------|-------|------------|-------------|------------|----------|-------|
| {name} | {model} | {identity} | {rate} | {rate} | {pri} | Active |

## Auth Policies
| Name | Model | User/Group | Phase |
|------|-------|------------|-------|
| {name} | {model} | {identity} | Active |

## API Keys
| Name | Prefix | Subscription | Expires | Created |
|------|--------|-------------|---------|---------|
| {name} | sk-oai-... | {sub} | {date} | {date} |

## Actions Taken
- Created MaaSSubscription: {name} ✓
- Created MaaSAuthPolicy: {name} ✓
- MaaSModelRef transitioned to Ready ✓

## GitOps Manifests
{YAML for ArgoCD deployment}
```

## Safety Constraints

- Never delete a MaaSSubscription or MaaSAuthPolicy without confirming no active API keys depend on it — deletion invalidates all keys issued under that subscription
- Both MaaSSubscription AND MaaSAuthPolicy are required together — creating one without the other leaves the MaaSModelRef in `Pending` state
- API keys are sensitive credentials — never log or display the full key value after initial creation; show only the prefix (`sk-oai-...`)
- Rate limit values are in tokens, not requests — set `tokensPerHour` and `tokensPerDay` to reasonable values (default: 1M/hour, 10M/day for individual users)
- Priority determines which subscription wins when a user matches multiple — document priority assignments to avoid conflicts
- The `models-as-a-service` namespace is shared — use clear naming conventions (`{model}-{user/group}-sub`) to avoid collisions
- All governance changes must go through Git (PR) — never apply subscription resources directly with `oc apply` in production
- Never expose the MaaS gateway externally without TLS termination configured on the Route

## Disconnected Environment Notes

- MaaS API keys are validated locally by Kuadrant via Kubernetes TokenReview — no external auth provider is required
- The maas-api service stores subscription and key data in PostgreSQL — ensure the `maas-db-config` secret points to a reachable database
- Usage tracking and observability dashboards require Prometheus metrics collection — verify the monitoring stack is operational in the disconnected cluster
- Gateway Route and TLS certificates must use internally trusted CAs — the default `router-certs-default` secret works if the OpenShift ingress controller is configured with internal certificates
- CSV usage export queries the local maas-api database — no external network access is needed for cost attribution reports

## Related Skills

- `maas-external-models` — Route inference to external cloud model providers through the MaaS gateway
- `rhoai-model-lifecycle` — Track model deployments through the RHOAI serving pipeline
- `model-promotion-workflow` — Promote models across environments with GitOps validation gates
