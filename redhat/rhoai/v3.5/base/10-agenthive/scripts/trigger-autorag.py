#!/usr/bin/env python3
"""Trigger a DSPA AutoRAG run from a checked-in JSON payload.

Discovers pipeline / version / experiment IDs on the cluster so git does not
hard-code live Kubeflow IDs. Does **not** run on Argo PostSync.

Usage:
  python3 platform/scripts/trigger-autorag.py \\
    --payload platform/autorag/rfp-run.json

Requires oc logged into the cluster with access to namespace rfp-agent.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

NS = "rfp-agent"
API = "https://localhost:8888/apis/v2beta1"
OC_CONTEXT = os.environ.get("OC_CONTEXT", "").strip()


def oc_base() -> list[str]:
    cmd = ["oc"]
    if OC_CONTEXT:
        cmd.extend(["--context", OC_CONTEXT])
    return cmd


def oc_json(*args: str) -> dict | list:
    out = subprocess.check_output([*oc_base(), *args], text=True)
    return json.loads(out)


def dspa_pod() -> str:
    pods = oc_json(
        "get", "pods", "-n", NS, "-l", "app=ds-pipeline-dspa", "-o", "json"
    )
    items = pods.get("items") or []
    ready = []
    for p in items:
        name = p["metadata"]["name"]
        if "ds-pipeline-dspa" not in name:
            continue
        cs = p.get("status", {}).get("containerStatuses") or []
        if all(c.get("ready") for c in cs) and cs:
            ready.append(name)
    if not ready:
        # fallback: any Running ds-pipeline-api-server
        raw = subprocess.check_output(
            [*oc_base(), "get", "pods", "-n", NS, "--no-headers"], text=True
        )
        for line in raw.splitlines():
            if "ds-pipeline-dspa" in line and "2/2" in line:
                return line.split()[0]
        raise SystemExit("No Ready ds-pipeline-dspa pod in rfp-agent")
    return ready[0]


def kfp(pod: str, method: str, path: str, body: dict | None = None) -> dict:
    cmd = [
        *oc_base(),
        "exec",
        "-n",
        NS,
        pod,
        "-c",
        "ds-pipeline-api-server",
        "--",
        "curl",
        "-sk",
        "-X",
        method,
        f"{API}{path}",
        "-H",
        "Content-Type: application/json",
    ]
    if body is not None:
        cmd.extend(["-d", json.dumps(body)])
    raw = subprocess.check_output(cmd, text=True)
    if not raw.strip():
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"KFP {method} {path} returned non-JSON: {raw[:500]}") from exc


def resolve_pipeline(pod: str, payload: dict) -> tuple[str, str]:
    pid = (payload.get("pipeline_id") or "").strip()
    vid = (payload.get("pipeline_version_id") or "").strip()
    name = payload.get("pipeline_name") or "documents-rag-optimization-pipeline"
    vname = payload.get("pipeline_version_name") or ""
    if pid and vid:
        return pid, vid
    pipelines = kfp(pod, "GET", "/pipelines?page_size=50")
    for p in pipelines.get("pipelines") or []:
        display = p.get("display_name") or p.get("name") or ""
        if display == name or name in display:
            pid = p["pipeline_id"]
            break
    if not pid:
        raise SystemExit(f"Pipeline not found: {name}")
    versions = kfp(pod, "GET", f"/pipelines/{pid}/versions?page_size=50")
    items = versions.get("pipeline_versions") or versions.get("versions") or []
    chosen = None
    for v in items:
        dn = v.get("display_name") or v.get("name") or ""
        if vname and (vname == dn or vname in dn):
            chosen = v
            break
        if "fixed" in dn.lower() and chosen is None:
            chosen = v
    if chosen is None and items:
        chosen = items[0]
    if not chosen:
        raise SystemExit(f"No versions for pipeline {pid}")
    vid = chosen.get("pipeline_version_id") or chosen.get("version_id")
    print(f"pipeline_id={pid} version_id={vid} version={chosen.get('display_name')}")
    return pid, vid


def resolve_experiment(pod: str, name: str) -> str:
    exps = kfp(pod, "GET", "/experiments?page_size=50")
    for e in exps.get("experiments") or []:
        if (e.get("display_name") or e.get("name")) == name:
            eid = e.get("experiment_id") or e.get("id")
            print(f"experiment_id={eid} (existing {name})")
            return eid
    created = kfp(
        pod,
        "POST",
        "/experiments",
        {"display_name": name, "description": f"AutoRAG experiment {name}"},
    )
    eid = created.get("experiment_id") or created.get("id")
    if not eid:
        raise SystemExit(f"Failed to create experiment {name}: {created}")
    print(f"experiment_id={eid} (created {name})")
    return eid


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--payload",
        default="platform/autorag/rfp-run.json",
        help="Path to run JSON in git",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the KFP run body without POSTing",
    )
    args = parser.parse_args()
    payload = json.loads(Path(args.payload).read_text())
    pod = dspa_pod()
    print(f"DSPA pod: {pod}")
    pid, vid = resolve_pipeline(pod, payload)
    eid = resolve_experiment(pod, payload.get("experiment_name") or "rfp-agent-autorag")
    body = {
        "display_name": payload["display_name"],
        "description": payload.get("description") or "",
        "experiment_id": eid,
        "pipeline_version_reference": {
            "pipeline_id": pid,
            "pipeline_version_id": vid,
        },
        "runtime_config": payload["runtime_config"],
    }
    if args.dry_run:
        print(json.dumps(body, indent=2))
        return 0
    result = kfp(pod, "POST", "/runs", body)
    run_id = result.get("run_id") or result.get("run", {}).get("id")
    state = result.get("state") or result.get("run", {}).get("state")
    err = result.get("error")
    print(f"run_id={run_id} state={state}")
    if err:
        print(f"error={err}", file=sys.stderr)
        return 1
    if not run_id:
        print(json.dumps(result, indent=2)[:2000], file=sys.stderr)
        return 1
    sandbox = "agents/rfp-agent/sandbox.yaml"
    print(
        f"After Succeeded, set OGX_VECTOR_STORE_ID on {sandbox} "
        "only (git). Do not edit platform/deploy/base/sandbox.yaml."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
