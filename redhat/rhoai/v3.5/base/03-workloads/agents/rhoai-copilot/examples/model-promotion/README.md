# Example: Model Promotion

Demonstrates promoting a model from development to staging via GitOps.

## User Prompt

> "Promote the fraud-detection model v3 from dev to staging"

## Expected Agent Behavior

1. Calls `get_registered_model` (RHOAI MCP) to verify model exists
2. Calls `list_model_versions` to confirm v3 is registered
3. Calls `check_deployment_prerequisites` for the staging namespace
4. Generates a Kustomize patch for the staging overlay
5. Creates a PR via GitHub MCP with the deployment configuration

## Sample Output

```
Model Promotion: fraud-detection v3 (dev → staging)

Pre-flight checks:
  ✓ Model fraud-detection v3 found in model registry
  ✓ Staging namespace 'ml-staging' exists and has serving runtime
  ✓ Sufficient GPU resources available (2x T4 requested, 4x available)
  ✓ Data connection for model storage configured

Generated configuration:
  - InferenceService YAML with v3 model URI
  - Resource requests matching production profile
  - Auto-scaling min=1, max=3

Action: I'll create a PR to your GitOps repo with these changes.

PR created: https://github.com/rrbanda/rhoai-deploy-gitops/pull/42
  Title: "Promote fraud-detection v3 to staging"
  Files: components/instances/model-serving/staging/fraud-detection-v3.yaml

ArgoCD will detect the change and deploy on next sync cycle.
```
