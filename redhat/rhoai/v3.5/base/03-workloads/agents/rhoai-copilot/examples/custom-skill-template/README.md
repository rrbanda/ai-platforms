# Example: adding a skill on AgentHive

Skills are authored under `skill-sources/` and deployed as flat ConfigMaps `skills/skill-<name>.yaml`.

## 1. Author the source

```bash
mkdir -p agents/rhoai-copilot/skill-sources/administer/gpu-driver-checker
# Write SKILL.md — see skill-sources/SKILL_SPEC.md and skill-sources/_template/SKILL.md.template
```

## 2. Generate the ConfigMap

```bash
python3 platform/scripts/sync-skills.py --agent rhoai-copilot
```

## 3. Wire the runtime (all required)

- `kustomization.yaml` — add `skills/skill-gpu-driver-checker.yaml`
- `sandbox.yaml` — volume + `mountPath: /mnt/skill-gpu-driver-checker`
- `startup.yaml` — append `gpu-driver-checker` to `SKILLS=`

```bash
python3 platform/scripts/check-skill-parity.py
```

## 4. Eval scenario (rhoai-copilot)

Copy `eval/scenarios/_template.yaml` to `eval/scenarios/gpu-driver-check.yaml`.

CI fails the PR if those lists diverge. There is no `configMapGenerator` path and no `skills/administer/` tree on the cluster.
