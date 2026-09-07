---
name: maas-external-models
description: "Configure routing of inference requests to external cloud model providers (AWS Bedrock, Azure OpenAI, Google Vertex AI) through the MaaS gateway with unified governance."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, MaaS, External Models, AWS Bedrock, Azure OpenAI, Google Vertex AI, Gateway, OIDC, Technology Preview]
---

# Route Inference to External Cloud Models via MaaS

Configure the MaaS gateway to route inference requests to external cloud model providers — AWS Bedrock, Azure OpenAI, and Google Vertex AI — while maintaining the same governance (subscriptions, authentication policies, rate limiting) as internal models. Users access all models through a consistent OpenAI-compatible API.

> **⚠️ TECHNOLOGY PREVIEW:** External model routing through MaaS and External OIDC authentication are Technology Preview features in Red Hat OpenShift AI. Technology Preview features are not supported with Red Hat production service level agreements (SLAs), might not be functionally complete, and are not recommended for production use. Provider connectivity and authentication mechanisms may change between releases.

## Trigger Conditions

- "Route requests to AWS Bedrock through MaaS"
- "Add Azure OpenAI models to the gateway"
- "Connect Google Vertex AI models to MaaS"
- "Use external models through the MaaS gateway"
- "Set up unified API access for cloud and local models"
- "Configure external OIDC for model access"
- "I want one API for both internal and cloud models"
- "Add a Bedrock model to my MaaS catalog"
- "Govern external model access with subscriptions"

## Required MCP Tools

| Server | Tool | Purpose |
|--------|------|---------|
| `mcp_rhoai` | `list_inference_services` | View existing models in the MaaS catalog |
| `mcp_rhoai` | `cluster_summary` | Verify MaaS and external model support are enabled |
| `mcp_openshift` | `resources_list` | List MaaSExternalModel CRs and related resources |
| `mcp_openshift` | `resources_get` | Inspect external model configuration and status |

## Procedure

### Phase 1: Prerequisites Verification

1. Call `mcp_rhoai.cluster_summary` to confirm:
   - RHOAI version ≥ 3.4
   - MaaS (AIGateway) is enabled and operational
   - External model routing capability is available

2. Verify MaaS gateway is healthy:
   ```bash
   oc get aigateway default-aigateway -o jsonpath='{.status.conditions}' | \
     jq '.[] | select(.type=="ModelsAsAServiceReady")'
   ```
   Expected: `status: "True"`

3. Confirm the target provider is supported:

   | Provider | API Compatibility | Authentication |
   |----------|-------------------|----------------|
   | AWS Bedrock | OpenAI-compatible via Bedrock Runtime | IAM credentials (Access Key + Secret) |
   | Azure OpenAI | OpenAI-compatible natively | API Key or Azure AD (OIDC) |
   | Google Vertex AI | OpenAI-compatible via Vertex endpoint | Service Account JSON key or Workload Identity |

### Phase 2: Configure Provider Credentials

4. Create a Kubernetes Secret with the provider credentials:

   **AWS Bedrock:**
   ```bash
   oc create secret generic maas-aws-bedrock-creds \
     -n models-as-a-service \
     --from-literal=AWS_ACCESS_KEY_ID='<access-key>' \
     --from-literal=AWS_SECRET_ACCESS_KEY='<secret-key>' \
     --from-literal=AWS_REGION='<region>'
   ```

   **Azure OpenAI:**
   ```bash
   oc create secret generic maas-azure-openai-creds \
     -n models-as-a-service \
     --from-literal=AZURE_OPENAI_API_KEY='<api-key>' \
     --from-literal=AZURE_OPENAI_ENDPOINT='https://<resource>.openai.azure.com'
   ```

   **Google Vertex AI:**
   ```bash
   oc create secret generic maas-google-vertex-creds \
     -n models-as-a-service \
     --from-file=GOOGLE_APPLICATION_CREDENTIALS='<service-account-key.json>' \
     --from-literal=GOOGLE_PROJECT_ID='<project-id>' \
     --from-literal=GOOGLE_REGION='<region>'
   ```

5. For External OIDC authentication (enterprise-wide access, Technology Preview):
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: maas-external-oidc-config
     namespace: models-as-a-service
   type: Opaque
   stringData:
     OIDC_ISSUER_URL: "https://login.example.com/realms/enterprise"
     OIDC_CLIENT_ID: "<client-id>"
     OIDC_CLIENT_SECRET: "<client-secret>"
     OIDC_SCOPES: "openid,email,groups"
   ```

### Phase 3: Register External Model

6. Create the MaaSExternalModel custom resource:

   **AWS Bedrock example:**
   ```yaml
   apiVersion: maas.opendatahub.io/v1alpha1
   kind: MaaSExternalModel
   metadata:
     name: bedrock-claude-sonnet
     namespace: models-as-a-service
   spec:
     provider:
       type: aws-bedrock
       credentialsSecret: maas-aws-bedrock-creds
       config:
         region: us-east-1
         modelId: anthropic.claude-3-5-sonnet-20241022-v2:0
     displayName: "Claude 3.5 Sonnet (Bedrock)"
     modelName: claude-3-5-sonnet  # name exposed in /v1/models
     capabilities:
       - chat
       - tool-calling
     routing:
       timeout: 120s
       retries: 2
       circuitBreaker:
         consecutiveErrors: 5
         interval: 30s
   ```

   **Azure OpenAI example:**
   ```yaml
   apiVersion: maas.opendatahub.io/v1alpha1
   kind: MaaSExternalModel
   metadata:
     name: azure-gpt4o
     namespace: models-as-a-service
   spec:
     provider:
       type: azure-openai
       credentialsSecret: maas-azure-openai-creds
       config:
         deploymentName: gpt-4o
         apiVersion: "2024-10-21"
     displayName: "GPT-4o (Azure)"
     modelName: gpt-4o
     capabilities:
       - chat
       - tool-calling
       - vision
     routing:
       timeout: 60s
       retries: 3
   ```

   **Google Vertex AI example:**
   ```yaml
   apiVersion: maas.opendatahub.io/v1alpha1
   kind: MaaSExternalModel
   metadata:
     name: vertex-gemini-pro
     namespace: models-as-a-service
   spec:
     provider:
       type: google-vertex
       credentialsSecret: maas-google-vertex-creds
       config:
         projectId: my-gcp-project
         region: us-central1
         modelId: gemini-1.5-pro
     displayName: "Gemini 1.5 Pro (Vertex AI)"
     modelName: gemini-1.5-pro
     capabilities:
       - chat
       - tool-calling
       - vision
     routing:
       timeout: 90s
       retries: 2
   ```

7. Apply the external model configuration:
   ```bash
   oc apply -f maas-external-model.yaml
   ```

8. Verify registration status:
   ```bash
   oc get maasexternalmodel <name> -n models-as-a-service \
     -o jsonpath='{.status.phase}'
   ```
   Expected: `Ready`

### Phase 4: Configure Governance

9. Create a MaaSSubscription for the external model (same as internal models):
   ```yaml
   apiVersion: maas.opendatahub.io/v1alpha1
   kind: MaaSSubscription
   metadata:
     name: <model-name>-sub
     namespace: models-as-a-service
   spec:
     modelRef:
       kind: MaaSExternalModel
       name: <external-model-name>
     owner:
       user: <oc-username>  # or group: <group-name>
     rateLimits:
       - window: 1h
         maxTokens: 1000000
       - window: 24h
         maxTokens: 10000000
     priority: 10
   ```

10. Create a MaaSAuthPolicy for the external model:
    ```yaml
    apiVersion: maas.opendatahub.io/v1alpha1
    kind: MaaSAuthPolicy
    metadata:
      name: <model-name>-auth
      namespace: models-as-a-service
    spec:
      modelRef:
        kind: MaaSExternalModel
        name: <external-model-name>
      authentication:
        type: openshift-token  # or external-oidc
      authorization:
        allowedUsers:
          - <username>
        allowedGroups:
          - <group-name>
    ```

11. For External OIDC authentication (Technology Preview):
    ```yaml
    spec:
      authentication:
        type: external-oidc
        oidcConfig:
          secretRef: maas-external-oidc-config
          usernameClaim: email
          groupsClaim: groups
    ```

12. Apply governance resources:
    ```bash
    oc apply -f subscription.yaml
    oc apply -f authpolicy.yaml
    ```

### Phase 5: Verification

13. Verify the external model appears in the MaaS catalog:
    ```bash
    MAAS_URL=$(oc get route maas-default-gateway -n openshift-ingress -o jsonpath='{.spec.host}')
    API_KEY="<your-api-key>"

    curl -s -H "Authorization: Bearer ${API_KEY}" \
      "https://${MAAS_URL}/maas-api/v1/models" | jq '.data[] | .id'
    ```
    Expected: external model name appears alongside internal models.

14. Test inference through the gateway:
    ```bash
    curl -X POST "https://${MAAS_URL}/v1/chat/completions" \
      -H "Authorization: Bearer ${API_KEY}" \
      -H "Content-Type: application/json" \
      -d '{
        "model": "<external-model-name>",
        "messages": [
          {"role": "user", "content": "Hello, what model are you?"}
        ],
        "max_tokens": 100
      }'
    ```

15. Verify governance is enforced:
    - Rate limiting: send requests exceeding the configured rate and confirm 429 response
    - Authentication: send request without valid token and confirm 401 response
    - Authorization: send request from unauthorized user and confirm 403 response

16. Call `mcp_openshift.resources_get` for the MaaSExternalModel to confirm:
    - `status.phase: Ready`
    - `status.lastSuccessfulConnection` is recent
    - No error conditions

## Output Format

```
# MaaS External Model Configuration Report

## ⚠️ Technology Preview Notice
External model routing and External OIDC are Technology Preview features.
Provider connectivity and authentication mechanisms may change between releases.

## External Model
- Name: {model-name}
- Display Name: {display-name}
- Provider: {aws-bedrock/azure-openai/google-vertex}
- Region: {region}
- Status: {Ready/Error}
- Capabilities: {chat, tool-calling, vision}

## Gateway Access
- MaaS URL: {gateway-url}
- Model ID in API: {model-name}
- OpenAI-compatible: Yes

## Governance
- Subscription: {sub-name} (status: {Active/Pending})
- Auth Policy: {auth-name} (status: {Active/Pending})
- Rate Limits: {tokens}/h, {tokens}/24h
- Authentication: {openshift-token/external-oidc}
- Authorized: {users/groups}

## Routing Configuration
- Timeout: {seconds}s
- Retries: {count}
- Circuit Breaker: {enabled/disabled}

## Verification
- Model listed in catalog: ✓/✗
- Inference test: ✓/✗ (latency: {ms}ms)
- Rate limiting enforced: ✓/✗
- Auth enforced: ✓/✗

## Usage Example
```bash
curl -X POST "https://{gateway-url}/v1/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"model": "{model-name}", "messages": [...]}'
```

## Next Steps
- {Add additional external models}
- {Configure cross-model fallback routing}
- {Set up monitoring for external provider latency}
```

## Safety Constraints

- Never store provider credentials (API keys, access keys, service account keys) in plain text — always use Kubernetes Secrets
- Do not expose cloud provider credentials in logs, events, or output
- Warn users about data sovereignty — requests routed to external providers leave the cluster and may cross geographic boundaries
- Verify the user has authorization to use the cloud provider account before configuring credentials
- Do not configure external models with unlimited rate limits — always set reasonable token budgets to control costs
- Warn that external model responses are not governed by the same security controls as internal models
- External OIDC configuration must use HTTPS endpoints — never configure HTTP OIDC issuers
- Do not share API keys across subscriptions — each user/team should have their own subscription and key
- Remind users that Technology Preview features may have security gaps not present in GA features

## Disconnected Environment Notes

- **External model routing is inherently incompatible with fully disconnected environments** — by definition, requests must reach external cloud APIs
- **Partially connected (proxy) environments**: Configure HTTP/HTTPS proxy settings in the MaaSExternalModel spec:
  ```yaml
  spec:
    provider:
      proxy:
        httpProxy: "http://proxy.internal:3128"
        httpsProxy: "http://proxy.internal:3128"
        noProxy: ".cluster.local,.svc"
  ```
- **Air-gapped with selective egress**: If the cluster allows egress only to specific external endpoints, ensure the provider API endpoints are in the egress allowlist:
  - AWS Bedrock: `bedrock-runtime.<region>.amazonaws.com`
  - Azure OpenAI: `<resource>.openai.azure.com`
  - Google Vertex AI: `<region>-aiplatform.googleapis.com`
- **MaaS controller images**: The MaaS controller itself must still be mirrored (same as internal MaaS setup)
- **Fallback strategy**: Configure internal models as fallbacks for when external providers are unreachable — use circuit breaker settings to trigger automatic fallback

## Related Skills

- `maas-subscription-manager` — Manage MaaS subscriptions, API keys, rate limiting, and usage tracking
- `rhoai-model-lifecycle` — Track model deployments through the RHOAI serving pipeline
- `model-promotion-workflow` — Promote models across environments with GitOps validation gates
