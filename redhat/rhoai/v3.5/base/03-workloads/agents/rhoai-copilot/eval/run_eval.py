#!/usr/bin/env python3
"""RHOAI Copilot Evaluation Runner (MVP).

Reads scenario YAML files, formats evaluation prompts, and produces
structured evaluation reports. Supports two modes:

  --mode=report   (default) Generate evaluation prompt + checklist per scenario
  --mode=score    Score a completed evaluation run from results/ directory

Usage:
  python eval/run_eval.py                          # Report all scenarios
  python eval/run_eval.py --scenario install-*     # Glob-match scenarios
  python eval/run_eval.py --persona sre            # Filter by persona
  python eval/run_eval.py --phase monitor          # Filter by phase
  python eval/run_eval.py --mode=score             # Score results
"""

import argparse
import fnmatch
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional

import yaml

SCENARIOS_DIR = Path(__file__).parent / "scenarios"
RUBRIC_PATH = Path(__file__).parent / "scoring" / "rubric.md"
RESULTS_DIR = Path(__file__).parent / "results"


def load_scenarios(
    scenario_glob: Optional[str] = None,
    persona: Optional[str] = None,
    phase: Optional[str] = None,
) -> List[Dict]:
    """Load and filter scenario YAML files."""
    scenarios = []
    for f in sorted(SCENARIOS_DIR.glob("*.yaml")):
        if f.name.startswith("_"):
            continue
        with open(f) as fh:
            data = yaml.safe_load(fh)
        if data is None:
            continue
        data["_file"] = f.name
        scenarios.append(data)

    if scenario_glob:
        scenarios = [s for s in scenarios if fnmatch.fnmatch(s["_file"], scenario_glob)]
    if persona:
        scenarios = [s for s in scenarios if s.get("persona") == persona]
    if phase:
        scenarios = [s for s in scenarios if s.get("phase") == phase]

    return scenarios


def format_eval_prompt(scenario: dict) -> str:
    """Generate a structured evaluation prompt from a scenario."""
    lines = [
        f"## Evaluation: {scenario['name']}",
        f"**Persona:** {scenario.get('persona', 'N/A')}",
        f"**Phase:** {scenario.get('phase', 'N/A')}",
        f"**Skill:** {scenario.get('skill', 'N/A')}",
        "",
        "### User Input",
        f"> {scenario['input']}",
        "",
    ]

    ctx = scenario.get("context", {})
    if ctx:
        lines.append("### Context")
        lines.append(f"- Cluster: {ctx.get('cluster', 'connected')}")
        for k, v in ctx.items():
            if k == "cluster":
                continue
            lines.append(f"- {k}: {json.dumps(v, default=str)}")
        lines.append("")

    tools = scenario.get("expected_tools", [])
    if tools:
        lines.append("### Expected MCP Tools")
        for t in tools:
            lines.append(f"- [ ] `{t}`")
        lines.append("")

    behaviors = scenario.get("expected_behavior", [])
    if behaviors:
        lines.append("### Expected Behavior Checklist")
        for b in behaviors:
            lines.append(f"- [ ] {b}")
        lines.append("")

    safety = scenario.get("safety_check", {})
    must_not = safety.get("must_not", [])
    if must_not:
        lines.append("### Safety Checks (must NOT do)")
        for s in must_not:
            lines.append(f"- [ ] VERIFY agent does NOT: {s}")
        lines.append("")

    scoring = scenario.get("scoring", {})
    if scoring:
        lines.append("### Scoring")
        for dim, scale in scoring.items():
            lines.append(f"- **{dim}**: _____ / {scale}")
        lines.append("")

    return "\n".join(lines)


def generate_report(scenarios: list[dict]) -> str:
    """Generate the full evaluation report."""
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    lines = [
        f"# RHOAI Copilot Evaluation Report",
        f"**Generated:** {timestamp}",
        f"**Scenarios:** {len(scenarios)}",
        "",
        "## Coverage Summary",
        "",
    ]

    personas = sorted(set(s.get("persona", "N/A") for s in scenarios))
    phases = sorted(set(s.get("phase", "N/A") for s in scenarios))
    skills = sorted(set(s.get("skill", "N/A") for s in scenarios))

    lines.append(f"- **Personas covered:** {', '.join(personas)}")
    lines.append(f"- **Phases covered:** {', '.join(phases)}")
    lines.append(f"- **Skills tested:** {len(skills)}")
    lines.append("")

    lines.append("## Scenario Index")
    lines.append("")
    lines.append("| # | Scenario | Persona | Phase | Skill |")
    lines.append("|---|----------|---------|-------|-------|")
    for i, s in enumerate(scenarios, 1):
        lines.append(
            f"| {i} | {s['name']} | {s.get('persona', 'N/A')} | "
            f"{s.get('phase', 'N/A')} | {s.get('skill', 'N/A')} |"
        )
    lines.append("")
    lines.append("---")
    lines.append("")

    for s in scenarios:
        lines.append(format_eval_prompt(s))
        lines.append("---")
        lines.append("")

    lines.append("## Aggregate Scoring")
    lines.append("")
    lines.append("| Scenario | Accuracy | Completeness | Safety | Other |")
    lines.append("|----------|:--------:|:------------:|:------:|:-----:|")
    for s in scenarios:
        lines.append(f"| {s['name']} | _/5 | _/5 | ___ | ___ |")
    lines.append("")
    lines.append(f"**Overall pass rate:** ___/{len(scenarios)} scenarios")
    lines.append("")

    return "\n".join(lines)


def score_results() -> str:
    """Score completed evaluation results from results/ directory."""
    if not RESULTS_DIR.exists():
        return "No results/ directory found. Run evaluations first."

    result_files = sorted(RESULTS_DIR.glob("*.json"))
    if not result_files:
        return "No result files found in results/."

    lines = ["# Evaluation Score Summary", ""]
    total = 0
    passed = 0
    for rf in result_files:
        with open(rf) as fh:
            result = json.load(fh)
        total += 1
        safety = result.get("safety", "unknown")
        if safety == "pass":
            passed += 1
        accuracy = result.get("accuracy", "?")
        completeness = result.get("completeness", "?")
        lines.append(f"- **{rf.stem}**: accuracy={accuracy}/5, "
                      f"completeness={completeness}/5, safety={safety}")

    lines.append("")
    lines.append(f"**Pass rate:** {passed}/{total} ({100*passed//max(total,1)}%)")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="RHOAI Copilot Evaluation Runner")
    parser.add_argument("--scenario", help="Glob pattern to filter scenarios")
    parser.add_argument("--persona", help="Filter by persona")
    parser.add_argument("--phase", help="Filter by lifecycle phase")
    parser.add_argument("--mode", choices=["report", "score"], default="report",
                        help="Mode: report (generate eval prompts) or score (aggregate results)")
    parser.add_argument("--output", help="Output file (default: stdout)")
    parser.add_argument("--list", action="store_true", help="List scenarios and exit")
    args = parser.parse_args()

    if args.mode == "score":
        output = score_results()
    else:
        scenarios = load_scenarios(args.scenario, args.persona, args.phase)

        if not scenarios:
            print("No scenarios matched the filters.", file=sys.stderr)
            sys.exit(1)

        if args.list:
            for s in scenarios:
                print(f"  {s['_file']:40s}  persona={s.get('persona','?'):20s}  "
                      f"phase={s.get('phase','?'):15s}  skill={s.get('skill','?')}")
            return

        output = generate_report(scenarios)

    if args.output:
        Path(args.output).write_text(output)
        print(f"Wrote evaluation report to {args.output}", file=sys.stderr)
    else:
        print(output)


if __name__ == "__main__":
    main()
