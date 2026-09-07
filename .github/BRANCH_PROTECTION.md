# GitHub Branch Protection — Required Status Checks

Configure in **Settings > Branches > main > Require status checks**:

## Required (block merge on failure)

| Workflow | Job | What it catches |
|---|---|---|
| Validate | `yaml-lint` | Malformed YAML anywhere in repo |
| Validate | `kustomize-validate` | Broken kustomization (missing resources, bad patches) |
| Validate | `argocd-app-validate` | Wrong repoURL, missing paths, duplicate app names |
| Validate | `sealed-secret-audit` | Plaintext secrets, bad SealedSecret format |
| Validate | `skill-parity` | Skills drift between sources and deployed ConfigMaps |
| Security | `secret-scan` | Leaked credentials, tokens, API keys |

## Advisory (reported, not blocking)

| Workflow | Job | What it catches |
|---|---|---|
| Validate | `helm-validate` | Helm chart lint/template errors |
| Validate | `python-lint` | Python style/import issues |
| Validate | `shell-lint` | Shell script errors |
| Validate | `rego-check` | Invalid OPA policy syntax |
| Validate | `containerfile-lint` | Dockerfile best practices |
| Security | `trivy-config` | K8s security misconfigurations |
| Security | `kubeconform-schema` | Invalid K8s resource schemas |
| Security | `rbac-audit` | Overly permissive RBAC (wildcard roles) |

## To configure via GitHub CLI

```bash
gh api repos/rrbanda/ai-platforms/branches/main/protection -X PUT \
  -f required_status_checks='{"strict":true,"contexts":["Validate / yaml-lint","Validate / kustomize-validate","Validate / argocd-app-validate","Validate / sealed-secret-audit","Validate / skill-parity","Security / secret-scan"]}' \
  -f enforce_admins=false \
  -f required_pull_request_reviews='{"required_approving_review_count":1}'
```
