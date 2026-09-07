#!/usr/bin/env python3
"""Fail if skill-sources, skills YAML, kustomization, sandbox mounts, and startup SKILLS= drift."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AGENTS = ROOT / "03-workloads" / "agents"


def skill_sources(agent_dir: Path) -> set[str]:
    names: set[str] = set()
    src = agent_dir / "skill-sources"
    if not src.is_dir():
        return names
    for skill_md in src.rglob("SKILL.md"):
        if skill_md.parent.name.startswith("_"):
            continue
        names.add(skill_md.parent.name)
    return names


def skill_yaml_names(agent_dir: Path) -> set[str]:
    skills = agent_dir / "skills"
    if not skills.is_dir():
        return set()
    names = set()
    for p in skills.glob("skill-*.yaml"):
        names.add(p.name[len("skill-") : -len(".yaml")])
    return names


def kustomize_skill_names(agent_dir: Path) -> set[str]:
    text = (agent_dir / "kustomization.yaml").read_text()
    names = set()
    for m in re.finditer(r"skills/skill-([a-z0-9-]+)\.yaml", text):
        names.add(m.group(1))
    return names


def startup_skills(agent_dir: Path) -> set[str]:
    text = (agent_dir / "startup.yaml").read_text()
    m = re.search(r'SKILLS="([^"]+)"', text)
    if not m:
        return set()
    return set(m.group(1).split())


def sandbox_skills(agent_dir: Path) -> set[str]:
    text = (agent_dir / "sandbox.yaml").read_text()
    return set(re.findall(r"/mnt/skill-([a-z0-9-]+)", text))


def check_agent(name: str) -> list[str]:
    agent_dir = AGENTS / name
    errors: list[str] = []
    sets = {
        "skill-sources": skill_sources(agent_dir),
        "skills/*.yaml": skill_yaml_names(agent_dir),
        "kustomization": kustomize_skill_names(agent_dir),
        "startup SKILLS=": startup_skills(agent_dir),
        "sandbox mounts": sandbox_skills(agent_dir),
    }
    nonempty = {k: v for k, v in sets.items() if v}
    if len(nonempty) < 2:
        errors.append(f"{name}: not enough skill lists to compare")
        return errors
    baseline_key, baseline = next(iter(nonempty.items()))
    for key, value in nonempty.items():
        if value != baseline:
            missing = sorted(baseline - value)
            extra = sorted(value - baseline)
            errors.append(
                f"{name}: {key} != {baseline_key} "
                f"(missing={missing or '-'} extra={extra or '-'})"
            )
    return errors


def main() -> int:
    errors: list[str] = []
    for agent_dir in sorted(AGENTS.iterdir()):
        if not (agent_dir / "kustomization.yaml").is_file():
            continue
        if not (agent_dir / "skill-sources").is_dir():
            continue
        errors.extend(check_agent(agent_dir.name))
    if errors:
        print("Skill parity check failed:\n", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1
    print("Skill parity OK for all agents.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
