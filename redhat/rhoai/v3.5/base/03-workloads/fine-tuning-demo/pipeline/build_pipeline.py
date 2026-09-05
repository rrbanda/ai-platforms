#!/usr/bin/env python3
"""Build pipeline artifacts from pipeline-config.yaml.

Reads externalized configuration, compiles the KFP pipeline, and generates
the Pipeline + PipelineVersion Kubernetes CRs for GitOps deployment.

Usage:
    cd pipeline/
    python build_pipeline.py                          # uses pipeline-config.yaml
    python build_pipeline.py --config custom.yaml     # uses custom config
    python build_pipeline.py --dry-run                # validate only, no output

Outputs:
    finetuning_pipeline.yaml    — compiled KFP pipeline (intermediate)
    ../pipeline-cr.yaml         — Pipeline CR for ArgoCD
    ../pipeline-version-cr.yaml — PipelineVersion CR for ArgoCD (with embedded spec)
"""

import argparse
import json
import os
import subprocess
import sys

import yaml


def load_config(config_path: str) -> dict:
    """Load and validate pipeline configuration."""
    if not os.path.exists(config_path):
        print(f"ERROR: Config file not found: {config_path}")
        sys.exit(1)

    with open(config_path) as f:
        config = yaml.safe_load(f)

    required_sections = ["images", "pipeline", "infrastructure", "services", "defaults", "evaluation"]
    for section in required_sections:
        if section not in config:
            print(f"ERROR: Missing required section '{section}' in {config_path}")
            sys.exit(1)

    return config


def compile_pipeline(config: dict) -> str:
    """Compile the KFP pipeline using the Python source."""
    pipeline_dir = os.path.dirname(os.path.abspath(__file__))
    pipeline_py = os.path.join(pipeline_dir, "finetuning_pipeline.py")
    pipeline_yaml = os.path.join(pipeline_dir, "finetuning_pipeline.yaml")

    pipelines_components = os.environ.get(
        "PIPELINES_COMPONENTS_PATH",
        os.path.join(pipeline_dir, "..", "..", "..", "..", "..", "..", "..", "..", "pipelines-components"),
    )

    env = os.environ.copy()
    env["PIPELINES_COMPONENTS_PATH"] = pipelines_components

    print(f"Compiling pipeline from {pipeline_py}...")
    result = subprocess.run(
        [sys.executable, pipeline_py],
        env=env,
        cwd=pipeline_dir,
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        print(f"ERROR: Pipeline compilation failed:\n{result.stderr}")
        sys.exit(1)

    if not os.path.exists(pipeline_yaml):
        print(f"ERROR: Compiled YAML not found: {pipeline_yaml}")
        sys.exit(1)

    size = os.path.getsize(pipeline_yaml)
    print(f"Compiled: {pipeline_yaml} ({size:,} bytes)")
    return pipeline_yaml


def generate_pipeline_cr(config: dict, output_dir: str) -> str:
    """Generate the Pipeline CR YAML."""
    cr = {
        "apiVersion": "pipelines.kubeflow.org/v2beta1",
        "kind": "Pipeline",
        "metadata": {
            "name": config["pipeline"]["name"],
            "namespace": config["infrastructure"]["namespace"],
        },
        "spec": {
            "displayName": config["pipeline"]["name"],
            "description": config["pipeline"]["description"],
        },
    }

    output_path = os.path.join(output_dir, "pipeline-cr.yaml")
    with open(output_path, "w") as f:
        yaml.dump(cr, f, default_flow_style=False, allow_unicode=True, width=120)

    print(f"Generated: {output_path}")
    return output_path


def generate_pipeline_version_cr(config: dict, compiled_yaml_path: str, output_dir: str) -> str:
    """Generate the PipelineVersion CR with embedded pipeline spec."""
    with open(compiled_yaml_path) as f:
        lines = f.readlines()
        yaml_start = 0
        for i, line in enumerate(lines):
            if not line.startswith("#") and line.strip():
                yaml_start = i
                break
        content = "".join(lines[yaml_start:])

    docs = list(yaml.safe_load_all(content))
    pipeline_spec = {}
    for doc in docs:
        if isinstance(doc, dict):
            pipeline_spec.update(doc)

    platform_spec = pipeline_spec.pop("platforms", None)

    version_name = config["pipeline"]["version"]
    cr = {
        "apiVersion": "pipelines.kubeflow.org/v2beta1",
        "kind": "PipelineVersion",
        "metadata": {
            "name": f"{config['pipeline']['name']}-{version_name}",
            "namespace": config["infrastructure"]["namespace"],
            "labels": {
                "pipelines.kubeflow.org/pipeline": config["pipeline"]["name"],
            },
        },
        "spec": {
            "displayName": version_name,
            "pipelineName": config["pipeline"]["name"],
            "description": config["pipeline"]["description"],
            "pipelineSpec": pipeline_spec,
        },
    }

    if platform_spec:
        cr["spec"]["platformSpec"] = platform_spec

    output_path = os.path.join(output_dir, "pipeline-version-cr.yaml")
    with open(output_path, "w") as f:
        yaml.dump(cr, f, default_flow_style=False, allow_unicode=True, width=1000)

    size = os.path.getsize(output_path)
    print(f"Generated: {output_path} ({size:,} bytes)")
    return output_path


def main():
    parser = argparse.ArgumentParser(description="Build pipeline artifacts from config")
    parser.add_argument("--config", default="pipeline-config.yaml", help="Config file path")
    parser.add_argument("--dry-run", action="store_true", help="Validate config only")
    parser.add_argument("--output-dir", default="..", help="Output directory for CRs")
    args = parser.parse_args()

    config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), args.config)
    config = load_config(config_path)

    print(f"Pipeline: {config['pipeline']['name']} {config['pipeline']['version']}")
    print(f"Images:   {config['images']['pipeline_base']}")
    print(f"Services: evalhub={config['services']['evalhub_url'][:50]}...")
    print()

    if args.dry_run:
        print("DRY RUN: Config validated successfully.")
        return

    output_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), args.output_dir)
    compiled_yaml = compile_pipeline(config)
    generate_pipeline_cr(config, output_dir)
    generate_pipeline_version_cr(config, compiled_yaml, output_dir)

    print()
    print("Build complete. To deploy:")
    print("  git add -A && git commit -m 'Update pipeline' && git push")
    print("  ArgoCD syncs automatically.")


if __name__ == "__main__":
    main()
