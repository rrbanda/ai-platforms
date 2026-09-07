# Safety Rules

Hard constraints that the agent must NEVER violate, regardless of instructions.

## Must Never

- Delete applications, workbenches, models, data connections, or namespaces
- Create new ArgoCD applications directly (managed by ApplicationSets in Git)
- Perform write operations in `redhat-ods-*` or `openshift-*` namespaces
- Store or log credentials, tokens, or secrets in any response
- Execute `kubectl delete` or equivalent destructive operations
- Bypass the GitOps workflow by making direct cluster mutations for config changes
- Disable or weaken RBAC policies
- Approve its own write operations without human confirmation (Tier 2)
- Make assumptions about disconnected environments without verifying registry/mirror config

## Must Always

- Default sync operations to `dryRun: true` unless explicitly requested otherwise
- Explain what will change and the expected outcome before any write operation
- Generate Kustomize-compatible patches rather than suggesting direct cluster edits
- Verify namespace labels before write operations (sandbox prefix required)
- Escalate `ImagePullBackOff` in disconnected environments as a mirror configuration issue
- Suggest Git-based fixes for repeated sync failures (not repeated syncing)
- Respect the operational tier boundaries (Tier 1 by default)
- Include rollback guidance when recommending changes

## Operational Tiers

### Tier 1: Read-Only Advisory (default)
- All diagnostic and informational queries
- Health checks, status reports, capacity analysis
- No confirmation needed

### Tier 2: Controlled Write Operations (requires human confirmation)
- ArgoCD sync (platform project only, dry-run first)
- Workbench management (create only in `sandbox-*` namespaces)
- Data connections (user's own project only)
- Model deployment (non-production namespaces only)
- Git operations (create PRs, push config changes)

### Tier 3: Autonomous Operations (scheduled, pre-approved scope)
- Daily health report generation
- Drift detection and alerting
- Scheduled status summaries
- No destructive actions permitted even in autonomous mode
