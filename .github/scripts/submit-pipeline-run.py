#!/usr/bin/env python3
"""Submit a pipeline run to DSPA via REST API.

Standalone script (no KFP SDK needed). Used by the CD GitHub Action
to trigger pipeline runs after CI passes, and can also be run locally.

Usage:
    python submit-pipeline-run.py --dry-run          # validate only
    python submit-pipeline-run.py                    # submit a run
    python submit-pipeline-run.py --run-name my-run  # custom name
"""

import argparse
import json
import os
import sys
import time
import urllib.request
import urllib.error
import ssl
import yaml


def load_pipeline_config(config_path: str) -> dict:
    """Load pipeline-config.yaml and extract default parameters."""
    if not os.path.exists(config_path):
        print(f"WARNING: Config not found at {config_path}, using built-in defaults")
        return {}
    with open(config_path) as f:
        return yaml.safe_load(f)


def dspa_request(url: str, token: str, method: str = "GET", body: dict = None) -> dict:
    """Make an authenticated request to the DSPA API."""
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }

    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)

    try:
        with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        error_body = e.read().decode() if e.fp else ""
        if e.code in (401, 403):
            print(f"AUTH ERROR ({e.code}): Check OPENSHIFT_PIPELINE_TOKEN")
            sys.exit(1)
        if e.code in (502, 503, 504):
            print(f"TRANSIENT ERROR ({e.code}): {error_body[:200]}")
            return None
        print(f"API ERROR ({e.code}): {error_body[:500]}")
        sys.exit(1)
    except urllib.error.URLError as e:
        print(f"CONNECTION ERROR: {e.reason}")
        return None


def find_pipeline(dspa_url: str, token: str, pipeline_name: str) -> str:
    """Find pipeline ID by name."""
    data = dspa_request(f"{dspa_url}/apis/v2beta1/pipelines?page_size=50", token)
    if not data:
        return None
    for p in data.get("pipelines", []):
        if p.get("display_name") == pipeline_name:
            return p["pipeline_id"]
    return None


def find_latest_version(dspa_url: str, token: str, pipeline_id: str) -> dict:
    """Find the latest pipeline version."""
    data = dspa_request(
        f"{dspa_url}/apis/v2beta1/pipelines/{pipeline_id}/versions?page_size=10&sort_by=created_at%20desc",
        token,
    )
    if not data or not data.get("pipeline_versions"):
        return None
    return data["pipeline_versions"][0]


def check_existing_run(dspa_url: str, token: str, run_name: str) -> bool:
    """Check if a run with this name already exists (idempotency)."""
    data = dspa_request(
        f"{dspa_url}/apis/v2beta1/runs?page_size=20&sort_by=created_at%20desc&filter="
        + urllib.request.quote(json.dumps({"predicates": [{"key": "name", "operation": "EQUALS", "string_value": run_name}]})),
        token,
    )
    if data and data.get("runs"):
        return True
    return False


def submit_run(dspa_url: str, token: str, pipeline_id: str, version_id: str,
               run_name: str, params: dict, namespace: str) -> dict:
    """Submit a pipeline run."""
    runtime_config = {"parameters": {}}
    for k, v in params.items():
        if isinstance(v, bool):
            runtime_config["parameters"][k] = {"boolValue": v}
        elif isinstance(v, int):
            runtime_config["parameters"][k] = {"intValue": str(v)}
        elif isinstance(v, float):
            runtime_config["parameters"][k] = {"doubleValue": v}
        elif isinstance(v, list):
            runtime_config["parameters"][k] = {"listValue": {"values": [{"stringValue": str(x)} for x in v]}}
        else:
            runtime_config["parameters"][k] = {"stringValue": str(v)}

    body = {
        "display_name": run_name,
        "pipeline_version_reference": {
            "pipeline_id": pipeline_id,
            "pipeline_version_id": version_id,
        },
        "runtime_config": runtime_config,
        "service_account": "pipeline-runner-dspa",
    }

    return dspa_request(f"{dspa_url}/apis/v2beta1/runs", token, method="POST", body=body)


def wait_for_start(dspa_url: str, token: str, run_id: str, timeout: int = 300) -> str:
    """Wait until the run transitions out of PENDING state."""
    start = time.time()
    while time.time() - start < timeout:
        data = dspa_request(f"{dspa_url}/apis/v2beta1/runs/{run_id}", token)
        if data:
            state = data.get("state", "PENDING")
            if state != "PENDING":
                return state
        time.sleep(10)
    return "TIMEOUT"


def main():
    parser = argparse.ArgumentParser(description="Submit a pipeline run to DSPA")
    parser.add_argument("--dspa-url", default=os.environ.get("DSPA_URL", ""))
    parser.add_argument("--token", default=os.environ.get("OPENSHIFT_PIPELINE_TOKEN", ""))
    parser.add_argument("--pipeline-name", default="finetuning-pipeline")
    parser.add_argument("--pipeline-id", default=os.environ.get("PIPELINE_ID", ""))
    parser.add_argument("--namespace", default=os.environ.get("NAMESPACE", "fine-tuning-demo"))
    parser.add_argument("--run-name", default=os.environ.get("RUN_NAME", ""))
    parser.add_argument("--technique", default="")
    parser.add_argument("--config", default="")
    parser.add_argument("--commit-sha", default=os.environ.get("GITHUB_SHA", "unknown")[:7])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not args.dspa_url:
        print("ERROR: --dspa-url or DSPA_URL env var required")
        sys.exit(1)
    if not args.token:
        print("ERROR: --token or OPENSHIFT_PIPELINE_TOKEN env var required")
        sys.exit(1)

    # Load config for default parameters
    config_paths = [
        args.config,
        "redhat/rhoai/v3.5/base/03-workloads/fine-tuning-demo/pipeline/pipeline-config.yaml",
        "pipeline/pipeline-config.yaml",
        "pipeline-config.yaml",
    ]
    config = {}
    for cp in config_paths:
        if cp and os.path.exists(cp):
            config = load_pipeline_config(cp)
            print(f"Loaded config from: {cp}")
            break

    defaults = config.get("defaults", {})
    technique = args.technique or defaults.get("technique", "lora")
    timestamp = time.strftime("%Y%m%d-%H%M")
    run_name = args.run_name or f"{technique}-{args.commit_sha}-{timestamp}"

    print("=" * 60)
    print("Pipeline Run Submission")
    print("=" * 60)
    print(f"  DSPA URL:   {args.dspa_url}")
    print(f"  Namespace:  {args.namespace}")
    print(f"  Run name:   {run_name}")
    print(f"  Technique:  {technique}")
    print(f"  Commit:     {args.commit_sha}")
    print(f"  Dry run:    {args.dry_run}")

    # Find pipeline
    pipeline_id = args.pipeline_id
    if not pipeline_id:
        print(f"\nLooking up pipeline '{args.pipeline_name}'...")
        pipeline_id = find_pipeline(args.dspa_url, args.token, args.pipeline_name)
        if not pipeline_id:
            print(f"ERROR: Pipeline '{args.pipeline_name}' not found")
            sys.exit(1)
    print(f"  Pipeline ID: {pipeline_id}")

    # Find latest version
    print("Finding latest pipeline version...")
    version = find_latest_version(args.dspa_url, args.token, pipeline_id)
    if not version:
        print("ERROR: No pipeline versions found")
        sys.exit(1)
    version_id = version["pipeline_version_id"]
    version_name = version.get("display_name", "unknown")
    print(f"  Version:     {version_name} ({version_id[:12]}...)")

    # Idempotency check
    print(f"Checking for existing run '{run_name}'...")
    if check_existing_run(args.dspa_url, args.token, run_name):
        print(f"  SKIPPED: Run '{run_name}' already exists (idempotent)")
        sys.exit(0)

    # Build parameters
    params = {
        "run_name": run_name,
        "technique": technique,
        "registry_stage": defaults.get("registry_stage", "dev"),
    }
    for key in ["base_model", "dataset_uri", "dataset_subset", "epochs", "learning_rate"]:
        if key in defaults:
            params[key] = defaults[key]

    print(f"\n  Parameters: {json.dumps(params, indent=4)}")

    if args.dry_run:
        print("\n  DRY RUN: Would submit run. Exiting.")
        print("=" * 60)
        sys.exit(0)

    # Submit
    print("\nSubmitting pipeline run...")
    result = submit_run(args.dspa_url, args.token, pipeline_id, version_id, run_name, params, args.namespace)
    if not result:
        print("ERROR: Failed to submit run (no response)")
        sys.exit(1)

    run_id = result.get("run_id", "unknown")
    print(f"  Run ID:      {run_id}")
    print(f"  State:       {result.get('state', 'PENDING')}")

    # Wait for start
    print("\nWaiting for run to start (up to 5 min)...")
    state = wait_for_start(args.dspa_url, args.token, run_id, timeout=300)
    print(f"  Final state: {state}")

    # Output for GH Action
    summary_file = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_file:
        with open(summary_file, "a") as f:
            f.write(f"### Pipeline Run Submitted\n")
            f.write(f"- **Run name:** `{run_name}`\n")
            f.write(f"- **Run ID:** `{run_id}`\n")
            f.write(f"- **Version:** `{version_name}`\n")
            f.write(f"- **State:** `{state}`\n")
            f.write(f"- **Technique:** `{technique}`\n")
            f.write(f"- **Commit:** `{args.commit_sha}`\n")

    output_file = os.environ.get("GITHUB_OUTPUT")
    if output_file:
        with open(output_file, "a") as f:
            f.write(f"run_id={run_id}\n")
            f.write(f"run_name={run_name}\n")
            f.write(f"state={state}\n")

    print("\n" + "=" * 60)
    print(f"DONE — Run '{run_name}' is {state}")
    print("=" * 60)

    if state in ("FAILED", "TIMEOUT"):
        sys.exit(1)


if __name__ == "__main__":
    main()
