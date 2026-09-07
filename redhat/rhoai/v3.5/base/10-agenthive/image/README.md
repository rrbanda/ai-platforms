# Hermes Agent Image — Two-Layer Build

## Architecture

```
Layer 1: hermes-runtime       (Hermes + UBI9 + Node.js)
    |                          Rebuilds only on Hermes version bump
    v                          ~10 min build, changes rarely
Layer 2: rfp-agent            (requirements.txt + sandbox structure)
    |                          Rebuilds on deps changes
    v                          ~2 min build, changes often
OpenShell Sandbox              (pod runs inside OpenShell sandbox)
```

## Images

| Image | Registry | Purpose |
|-------|----------|---------|
| `hermes-runtime` | `ghcr.io/rrbanda/hermes-runtime:<version>` | Shared base: Hermes + system deps. Reusable by any agent. |
| `rfp-agent` | `ghcr.io/rrbanda/agenthive-agent:latest` | RFP-specific: pymilvus, mlflow, pypandoc, etc. |

## CI/CD (Automated via GitHub Actions)

| Workflow | Trigger | Builds |
|----------|---------|--------|
| `ci-build-hermes-runtime` | `image/HERMES_VERSION` or `Containerfile.runtime` change | Layer 1 |
| `ci-build-rfp-agent` | `requirements.txt` or `Containerfile.agent` change, or after Layer 1 | Layer 2 |
| `check-hermes-update` | Weekly cron (Monday 08:00 UTC) | Auto-PR if new Hermes release |
| `ci-lint` | Any PR | Validates YAML, Kustomize, scans for secrets |

No manual builds needed for normal development.

## Local Build (when needed)

```bash
cd image/

# Build Layer 1 (only if Hermes version changed)
podman build --platform linux/amd64 \
  -f Containerfile.runtime \
  -t ghcr.io/rrbanda/hermes-runtime:$(cat HERMES_VERSION) .

# Build Layer 2 (after Layer 1 exists)
podman build --platform linux/amd64 \
  -f Containerfile.agent \
  --build-arg RUNTIME_IMAGE=ghcr.io/rrbanda/hermes-runtime:$(cat HERMES_VERSION) \
  -t ghcr.io/rrbanda/agenthive-agent:latest .
```

## Updating Hermes Version

The `check-hermes-update` workflow auto-detects new releases weekly and opens a PR.
To update manually:

```bash
echo "v2026.9.01" > image/HERMES_VERSION
# Also update the ARG in Containerfile.runtime to match
git commit -am "chore: bump Hermes to v2026.9.01"
git push
```

## File Layout

```
image/
  HERMES_VERSION           <- pinned Hermes version (source of truth)
  Containerfile.runtime    <- Layer 1: UBI9 + Hermes + Node.js + ripgrep
  Containerfile.agent      <- Layer 2: FROM runtime + requirements.txt
  Containerfile            <- (legacy, kept for reference)
  requirements.txt         <- Python deps for the RFP agent
  build-and-push.sh        <- Local convenience script
  README.md                <- this file
```

## What the Image Provides (for OpenShell Sandboxes)

The `rfp-agent` image is designed to run inside an **OpenShell sandbox**:

- The **Agent Sandbox CRD** creates the pod
- The **OpenShell supervisor** is injected as an init container (from `ghcr.io/nvidia/openshell/supervisor`)
- The agent's **SOUL.md, config, skills** are mounted via ConfigMaps at runtime
- The **OpenShell gateway** handles mTLS, LLM provider routing, and network policy enforcement

The image itself contains only the runtime environment — no secrets, no agent-specific config.

## Security

- Public image on GHCR (no pull secrets needed on OpenShift)
- Built on UBI 9 (Red Hat Universal Base Image) for enterprise compliance
- Trivy scanned for CVEs in CI before push
- No credentials embedded in the image
- Hermes version pinned (not floating `:latest` from upstream)
