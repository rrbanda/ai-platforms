#!/usr/bin/env python3
"""Regenerate agents/<name>/skills/skill-*.yaml from skill-sources/**/SKILL.md."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TEMPLATE = """apiVersion: v1
kind: ConfigMap
metadata:
  name: skill-{name}
  labels:
    app.kubernetes.io/part-of: {agent}
    app.kubernetes.io/component: skill
data:
  SKILL.md: |
{body}
"""


def indent_body(text: str) -> str:
    lines = text.splitlines()
    if lines and lines[0].startswith("---"):
        # Keep front matter + markdown, indent every line 4 spaces for YAML block
        pass
    return "\n".join("    " + line if line else "" for line in lines)


def sync_agent(agent: str) -> int:
    agent_dir = ROOT / "agents" / agent
    src = agent_dir / "skill-sources"
    dest = agent_dir / "skills"
    if not src.is_dir():
        print(f"No skill-sources/ in {agent_dir}", file=sys.stderr)
        return 1
    dest.mkdir(exist_ok=True)
    written = []
    for skill_md in sorted(src.rglob("SKILL.md")):
        name = skill_md.parent.name
        body = indent_body(skill_md.read_text())
        out = dest / f"skill-{name}.yaml"
        out.write_text(TEMPLATE.format(name=name, agent=agent, body=body))
        written.append(name)
    print(f"{agent}: wrote {len(written)} skill ConfigMaps: {', '.join(written)}")
    print("Still required by hand if you added a skill:")
    print("  - kustomization.yaml resources")
    print("  - sandbox.yaml volume + volumeMount /mnt/skill-<name>")
    print("  - startup.yaml SKILLS=")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--agent", required=True, help="Directory name under agents/")
    args = parser.parse_args()
    return sync_agent(args.agent)


if __name__ == "__main__":
    raise SystemExit(main())
