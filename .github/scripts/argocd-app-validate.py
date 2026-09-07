#!/usr/bin/env python3
"""Validate all ArgoCD Application YAMLs for correctness.

Checks:
  - spec.source.path exists on disk
  - spec.project is a known project name
  - No duplicate metadata.name across all Application files
  - repoURL points to ai-platforms.git (not external repos)
"""

from __future__ import annotations

import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
VALID_PROJECTS = {"default", "rhoai-platform", "rhoai-config", "rhoai-workloads", "rhoai-spokes"}
VALID_REPO = "https://github.com/rrbanda/ai-platforms.git"
HELM_REPOS = {"ghcr.io/nvidia/openshell", "https://charts.openshift.io"}

APP_DIRS = [
    REPO_ROOT / "redhat" / "rhoai" / "v3.5" / "base" / "applications",
    REPO_ROOT / "redhat" / "rhoai" / "v3.5" / "base" / "10-agenthive" / "apps",
]

# Files that exist on disk but are commented out of their kustomization
# (kept as reference, not deployed). Exclude from duplicate-name checks.
EXCLUDED_FILES = {
    "loan-agent.yaml",  # Managed by applications/13-loan-agent.yaml instead
    "app-of-apps.yaml",  # Managed by applications/14-agenthive.yaml instead
    "openshell.yaml",  # Managed by applications/09b-openshell.yaml instead
    "evalhub.yaml",  # Commented out (RHOAI 3.5 EA2 CRDs not available)
}


def find_app_yamls() -> list[Path]:
    files = []
    for d in APP_DIRS:
        if d.is_dir():
            for f in sorted(d.glob("*.yaml")):
                if f.name == "kustomization.yaml":
                    continue
                files.append(f)
    return files


def validate_app(path: Path, seen_names: dict[str, Path]) -> list[str]:
    errors = []
    try:
        docs = list(yaml.safe_load_all(path.read_text()))
    except yaml.YAMLError as e:
        return [f"{path.name}: invalid YAML: {e}"]

    for doc in docs:
        if not doc or doc.get("kind") != "Application":
            continue

        name = doc.get("metadata", {}).get("name", "UNKNOWN")
        rel = path.relative_to(REPO_ROOT)

        if name in seen_names:
            other = seen_names[name].relative_to(REPO_ROOT)
            errors.append(f"{rel}: duplicate name '{name}' (also in {other})")
        else:
            seen_names[name] = path

        project = doc.get("spec", {}).get("project", "")
        if project not in VALID_PROJECTS:
            errors.append(f"{rel}: unknown project '{project}' (valid: {VALID_PROJECTS})")

        spec = doc.get("spec", {})
        sources = []
        if "source" in spec:
            sources.append(spec["source"])
        if "sources" in spec:
            sources.extend(spec["sources"])

        for src in sources:
            repo = src.get("repoURL", "")
            if repo and repo not in HELM_REPOS and repo != VALID_REPO:
                errors.append(f"{rel}: external repoURL '{repo}' (expected {VALID_REPO})")

            src_path = src.get("path", "")
            if src_path:
                full = REPO_ROOT / src_path
                if not full.is_dir():
                    errors.append(f"{rel}: path '{src_path}' does not exist on disk")

    return errors


def main() -> int:
    seen_names: dict[str, Path] = {}
    errors: list[str] = []

    app_files = find_app_yamls()
    if not app_files:
        print("ERROR: No Application YAML files found", file=sys.stderr)
        return 1

    for f in app_files:
        if f.name in EXCLUDED_FILES:
            continue
        errors.extend(validate_app(f, seen_names))

    if errors:
        print(f"ArgoCD Application validation failed ({len(errors)} errors):\n", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1

    print(f"ArgoCD Application validation OK ({len(seen_names)} apps checked).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
