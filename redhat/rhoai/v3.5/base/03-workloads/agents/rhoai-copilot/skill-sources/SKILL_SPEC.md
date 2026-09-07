# Skill Specification

A skill is a self-contained capability that teaches the agent how to perform a specific task within the RHOAI lifecycle.

## File Structure

Each skill is a single `SKILL.md` file in its own directory:

```
skills/<lifecycle-phase>/<skill-name>/SKILL.md
```

## Required Sections

Every SKILL.md must contain these sections:

### 1. Title (H1)
Clear, action-oriented name describing what the skill does.

### 2. Description
One paragraph explaining the skill's purpose and when to invoke it.

### 3. Trigger Conditions
Bullet list of user requests or system states that should activate this skill.

### 4. Required MCP Tools
Which MCP servers and specific tools the skill depends on.

### 5. Procedure
Step-by-step instructions the agent follows to execute the skill. Must be deterministic and repeatable.

### 6. Output Format
What the agent should return to the user (report, YAML, table, etc.).

### 7. Safety Constraints
Skill-specific safety rules beyond the global rules in `agent/rules.md`.

## Optional Sections

- **Examples**: Sample input/output pairs
- **Disconnected Environment Notes**: Adjustments needed for air-gapped clusters
- **Related Skills**: Links to complementary skills

## Lifecycle Phases

Skills are organized under these directories matching the RHOAI documentation:

| Directory | Phase | Description |
|-----------|-------|-------------|
| `platform-setup/` | Platform Setup | Deploying RHOAI operators and prerequisites |
| `plan/` | Plan | Capacity planning, resource estimation, architecture |
| `administer/` | Administer | Platform configuration, DSC management, upgrades |
| `develop/` | Develop | Workbenches, experiments, pipelines, debugging |
| `train/` | Train | Training job management, distributed training |
| `evaluate/` | Evaluate | Model evaluation, benchmarking, comparison |
| `deploy/` | Deploy | Model serving, promotion, lifecycle |
| `monitor/` | Monitor | Health checks, observability, incident response |
| `maintain-safety/` | Maintain Safety | Guardrails, bias detection, compliance |

## Naming Conventions

- Directory names use `kebab-case`
- Skill names should be descriptive: `rhoai-disconnected-deploy`, not `deploy-skill-1`
- Prefix with `rhoai-` for RHOAI-specific skills, `argocd-` for GitOps skills
