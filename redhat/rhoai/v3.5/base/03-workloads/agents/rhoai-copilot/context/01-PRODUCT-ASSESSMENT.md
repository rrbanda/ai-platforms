# 01 — Product Readiness Assessment

> Product maturity scoring using a 12-dimension Product Readiness Matrix.
> Framework: Each dimension scored 1-5 (1=concept, 5=enterprise-ready).
> Last updated: 2026-08-22

---

## Overall Score: 3.0 / 5.0 — Production-Ready (Post H1)

Strong foundations in agent identity, safety model, and MCP integration. H1 hardening raised testing (1.0→3.5), release engineering (1.0→3.5), security (2.0→3.0), and documentation (2.5→3.5). Remaining gaps in observability, multi-tenancy, and capability expansion (train/evaluate/maintain-safety phases still empty) are H2 priorities.

---

## Dimension Scores

### 1. Core Functionality — 3.0 / 5.0

**What exists:**
- 22 skills across 6 active lifecycle phases
- Clear skill specification (SKILL_SPEC.md) with required/optional sections
- Skills cover platform-setup (4), plan (3), administer (3), develop (3), deploy (4), monitor (5)
- Two skill styles: MCP-centric Hermes skills and operational MaaS skills with shell scripts
- Workflows compose skills into multi-step procedures (3 workflows)

**What's missing:**
- 3 entire lifecycle phases are empty (train, evaluate, maintain-safety = 0 skills)
- 9 planned skills exist only as names in README placeholders
- No skill versioning or compatibility declarations
- Workflow engine is informal (Hermes cron, not a dedicated executor reading YAML)
- Inline workflow steps have no skill backing (drift-detection classify step)

**To reach 5.0:** Fill all 9 lifecycle phases, formalize workflow execution, add skill versioning.

---

### 2. Safety / Governance — 3.0 / 5.0

**What exists:**
- `agent/rules.md` defines hard constraints (Must Never / Must Always)
- 3-tier autonomy model (Read-Only → Confirmed Write → Scheduled Non-Destructive)
- Write operations restricted to `sandbox-*` namespaces
- No deletes permitted at any tier
- `config.yaml` whitelists specific MCP tools per server
- Protected via CODEOWNERS (rules.md changes require @rrbanda approval)
- Skill-level safety constraints supplement global rules

**What's missing:**
- No audit trail (agent actions not logged to immutable store)
- No compliance reporting (SOC2, HIPAA, FedRAMP readiness)
- No role-based access within the agent (single user model)
- No rate limiting on tool calls
- No PII/secret detection in agent responses beyond the "must not store" rule
- No formal approval workflow tracking (Tier 2 confirmations are conversational only)

**To reach 5.0:** Implement audit logging, compliance frameworks, RBAC within agent, formal approval trails.

---

### 3. Testing / Evaluation — 1.0 / 5.0

**What exists:**
- 3 eval scenarios in YAML format (diagnose-sync-failure, disconnected-deploy, platform-health-check)
- Scoring rubric with 4 dimensions (accuracy 0-5, completeness 0-5, safety pass/fail, tool_efficiency 0-3)
- Plus scenario-specific dimensions (disconnected_awareness, presentation)
- Eval scenarios link to personas and skills
- `make eval` target exists (but is a stub)

**What's missing:**
- `make eval` prints scenario count but does not execute anything
- Only 3 scenarios cover 2 of 5 personas and 3 of 22 skills
- No automated eval runner
- No golden transcripts or expected tool traces
- No integration tests for MCP server connectivity
- No skill regression testing
- No CI integration for eval (validate.yaml only checks format)
- No results directory (documented but gitignored/absent)
- No eval for workflows
- No adversarial / red-team scenarios

**To reach 5.0:** Build eval runner, minimum 1 scenario per skill (22+), CI integration, golden transcripts, adversarial tests.

---

### 4. Observability — 1.0 / 5.0

**What exists:**
- Hermes dashboard on port 18789 with basic auth
- Dashboard exposed via OpenShift Route with TLS edge
- Session search enabled (Hermes toolset)
- Memory enabled (though providers list is empty)

**What's missing:**
- No agent telemetry (tool call counts, latencies, error rates, token usage)
- No OpenTelemetry / tracing integration
- No metrics endpoint (Prometheus/ServiceMonitor)
- No structured logging (JSON logs to aggregator)
- No alerting on agent failures
- No cost tracking (LLM token spend)
- No performance SLOs
- No user interaction analytics

**To reach 5.0:** OpenTelemetry instrumentation, Prometheus metrics, structured logging, cost tracking, SLOs.

---

### 5. Multi-tenancy — 1.0 / 5.0

**What exists:**
- Single-tenant design (one agent instance per cluster)
- Namespace-scoped write restrictions (`sandbox-*`)
- Delegation supports up to 3 concurrent children (Hermes toolset)

**What's missing:**
- No per-team or per-user agent instances
- No namespace isolation per tenant
- No data separation between users
- No usage quotas per team
- No tenant-aware skill routing
- No multi-cluster management from single agent

**To reach 5.0:** Namespace-scoped agent instances, tenant isolation, usage quotas, multi-cluster federation.

---

### 6. Security Hardening — 2.0 / 5.0

**What exists:**
- Container runs as non-root with all capabilities dropped
- ClusterRoleBinding to `cluster-reader` (read-only cluster access)
- RHOAI MCP has custom `rhoai-mcp-reader` ClusterRole (scoped read)
- Secrets stored in OpenShift Secret (not in repo)
- `config.yaml` uses `${VAR}` substitution resolved at runtime
- `.gitignore` excludes `*.env`, credentials, keys
- Web search and browser disabled in agent config
- SECURITY.md exists

**What's missing:**
- No NetworkPolicy for agent or MCP server pods
- No PodSecurity standards enforcement (restricted profile)
- No secret rotation guidance or automation
- No network segmentation between agent and MCP servers
- No mTLS between agent and HTTP MCP servers
- No image signing or SBOM
- No vulnerability scanning in CI
- No audit logging (covered in Safety dimension)
- External Secrets mentioned only briefly (no full guide)

**To reach 5.0:** NetworkPolicy, PodSecurity, mTLS, image signing, SBOM, vuln scanning, secret rotation.

---

### 7. CI/CD — 2.0 / 5.0

**What exists:**
- `validate.yaml`: skill format checks, kustomize build validation, yamllint
- `build-image.yaml`: build + push Hermes image to ghcr.io on main changes
- Makefile targets: validate, build, push, deploy, undeploy, status, logs, restart
- Issue templates for bugs and new skills

**What's missing:**
- No skill testing (only format validation, not behavioral)
- No integration tests (MCP connectivity, tool call round-trips)
- No eval in CI pipeline
- No release automation (no tagging, no semver, no CHANGELOG generation)
- No PR checks beyond format validation
- No container image scanning
- No multi-architecture builds (known issue: ARM vs AMD64)
- No staging/preview environments
- No deployment verification tests post-deploy

**To reach 5.0:** Behavioral skill tests, integration tests, eval in CI, release automation, image scanning, multi-arch.

---

### 8. Documentation — 2.5 / 5.0

**What exists:**
- Deployment guide (strongest doc — 492 lines, battle-tested on OCP 4.18)
- MCP server setup guide (838 lines, per-server configs)
- Troubleshooting guide (442 lines, real deployment issues)
- Credential obtaining guide (272 lines)
- Quickstart (105 lines, 4-6 step path)
- Architecture and autonomy tiers concepts
- Environment variables reference
- Disconnected setup guide (77 lines, thin)
- Custom skills guide (84 lines)
- 4 example interaction READMEs

**What's missing:**
- Broken cross-links (disconnected-setup.md path is wrong in 3 places)
- Stale skill count (19 vs actual 22) in architecture doc
- Phantom paths referenced (agent/profiles/, overlays/disconnected/)
- No docs index (navigation depends on root README)
- No skills catalog documentation
- No workflows guide
- No day-2 operations guide
- No upgrade or compatibility matrix
- No API reference for MCP tools
- No runnable examples (current examples are narrative only)
- No eval/personas documentation in docs/
- No security hardening guide
- No multi-tenancy or scaling guide

**To reach 5.0:** Fix broken links, add skills catalog, workflows guide, day-2 ops, API reference, runnable examples.

---

### 9. Disconnected Support — 2.5 / 5.0

**What exists:**
- 2 dedicated skills (rhoai-disconnected-deploy, rhoai-disconnected-helper)
- Other skills have "Disconnected Environment Notes" sections
- Agent config disables web search and browser (works offline)
- Disconnected-first mentioned in AGENTS.md rules
- MCP servers designed for in-cluster HTTP (no external dependencies)
- ArgoCD binary baked into image (no npm at runtime)
- GitHub MCP documented as replaceable (Gitea/GitLab alternatives)

**What's missing:**
- `runtimes/hermes/overlays/disconnected/` referenced in docs but does not exist
- No tested end-to-end disconnected deployment flow
- No kustomize overlay for disconnected environments
- `agent/profiles/connected.env` and `disconnected.env` referenced but don't exist
- Node.js + npm installed at build time (packages could be vendored)
- Disconnected setup guide is thin (77 lines) vs deployment guide (492 lines)
- No image mirror list / ImageSetConfiguration template in repo

**To reach 5.0:** Create disconnected overlay, profile files, vendored deps, tested e2e flow, ImageSetConfig templates.

---

### 10. Extensibility — 2.0 / 5.0

**What exists:**
- SKILL_SPEC.md defines the skill format (required + optional sections)
- `_template/SKILL.md.template` exists for creating new skills
- Skills are framework-agnostic (Markdown, not Hermes-specific code)
- Skills mounted as ConfigMaps (easy to add/remove via kustomization.yaml)
- Hermes skill curator enabled (auto-discovery)
- Custom skills guide in docs
- New-skill issue template in GitHub

**What's missing:**
- No plugin API or SDK for skill development
- No skill marketplace or registry
- No skill dependency management
- No skill versioning
- No skill testing framework
- No hooks or extension points in workflows
- No custom MCP server template or guide
- No third-party skill integration pattern

**To reach 5.0:** Skill SDK, marketplace, versioning, dependency management, testing framework.

---

### 11. Release / Versioning — 1.0 / 5.0

**What exists:**
- CHANGELOG.md exists (Unreleased section only, no versions)
- Container image tagged as `latest`
- GitHub Actions can build on demand

**What's missing:**
- No semantic versioning
- No release process or runbook
- No version tags in git
- No GitHub Releases
- No compatibility matrix (agent version vs RHOAI version vs OCP version)
- No upgrade path documentation
- No breaking change policy
- No deprecation process
- Image tagged `latest` only (no versioned tags)

**To reach 5.0:** Semver, release automation, versioned images, compatibility matrix, upgrade path docs.

---

### 12. Operational Maturity — 2.0 / 5.0

**What exists:**
- 3 workflows (daily health, drift detection, incident response)
- Hermes cronjob toolset enabled for scheduled operations
- Escalation hooks in workflows (log-and-continue, alert-channel, create-github-issue, notify-oncall)
- Makefile targets for ops (status, logs, restart)
- validate-deployment.sh script
- Incident runbook skill with P1-P4 severity levels

**What's missing:**
- No alerting integrations implemented (Slack, PagerDuty, Teams)
- No SLO/SLA definitions
- No runbook automation beyond skill content
- No change management process
- No disaster recovery plan
- No backup/restore procedures
- No scaling guidance (horizontal or vertical)
- No performance benchmarks for the agent itself
- Workflow execution is informal (no engine reads the YAML files directly)

**To reach 5.0:** Alerting integrations, SLOs, DR plan, scaling guide, formal workflow engine.

---

## Maturity Radar Summary

```
                    Core Func [3.0]
                         ╱╲
         Ops Maturity   ╱  ╲   Safety/Gov
             [2.0]     ╱    ╲    [3.0]
                      ╱      ╲
        Release/Ver  ╱        ╲  Testing
            [1.0]   │          │   [1.0]
                     │          │
       Extensibility │          │ Observability
            [2.0]    │          │    [1.0]
                      ╲        ╱
     Disconnected      ╲      ╱  Multi-tenancy
          [2.5]         ╲    ╱      [1.0]
                         ╲  ╱
            Docs [2.5]    ╲╱    Security [2.0]
                      CI/CD [2.0]
```

---

## Key Takeaway

The agent has a **strong conceptual foundation** (identity, safety model, skill architecture, MCP integration) but is at **early production maturity**. The largest gaps are in quality assurance (testing/eval), operational tooling (observability, alerting), and release engineering. These are the areas where enterprise adoption would be blocked.
