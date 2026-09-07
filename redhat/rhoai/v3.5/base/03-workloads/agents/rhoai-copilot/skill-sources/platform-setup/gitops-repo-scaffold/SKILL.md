---
name: gitops-repo-scaffold
description: "Scaffold a GitOps deployment repo for RHOAI by reading battle-tested templates, substituting environment values, and pushing to the user's Git repo via GitHub MCP. Two-phase: scaffold first, finalize after mirroring."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, GitOps, ArgoCD, Scaffold, Repository, Disconnected, Deployment]
---

# GitOps Repo Scaffold for RHOAI Deployment

Scaffolds a user's own GitOps deployment repository for Red Hat OpenShift AI by reading template manifests from `manifests/disconnected/`, substituting environment-specific values, and pushing the customized files to the user's Git repo via GitHub MCP.

Operates in two phases because not all values are available upfront — some depend on outputs from mirroring steps.

## Trigger Conditions

- "Set up a GitOps repo for deploying RHOAI"
- "Create a deployment repo for RHOAI"
- "Scaffold my RHOAI GitOps repository"
- "Initialize a GitOps repo for disconnected RHOAI"
- "Help me create the Git repo structure for RHOAI deployment"
- "Update my deployment repo with the mirror details"
- "Finalize my RHOAI deployment repo after mirroring"

## Required MCP Tools

| Server | Tool | Phase | Purpose |
|--------|------|-------|---------|
| GitHub | push_files | 1, 2 | Push customized files to the user's repo in a single commit |
| GitHub | get_file_contents | 2 | Read existing files to update Phase 2 placeholders |
| GitHub | create_branch | 1 | Create deployment branch if needed |
| GitHub | list_branches | 1 | Check if branch already exists |
| RHOAI | cluster_summary | 1 | Check if RHOAI is already installed |
| OpenShift | resources_list | 1 | Check cluster state (CatalogSources, namespaces) |

---

## Phase 1: Scaffold (Before Mirroring)

### When to Use

The user wants to set up a GitOps repo for RHOAI deployment but has NOT yet run oc-mirror or installed a mirror registry.

### Step 1: Gather Requirements

Ask the user these questions (use the agent's question tool for each):

1. **Repo owner and name** — e.g., `myorg/rhoai-deploy`. The repo must already exist on GitHub (the agent cannot create repos via MCP).
2. **Connected or disconnected?** — determines which templates to use.
3. **OCP version** — e.g., `4.20` (minor version only).
4. **RHOAI version** — e.g., `3.4.2` (full version).
5. **Mirror registry URL** — e.g., `bastion.lab:8443` (disconnected only).
6. **Components to enable** — which DSC components: KServe, workbenches, pipelines, model registry, ray, kueue, trustyai, training operator. Default: KServe + workbenches + pipelines + model registry.
7. **GPU workloads needed?** — determines if NFD + GPU operator are included.
8. **Branch name** — default: `main`.

### Step 2: Derive Computed Values

From the user's answers, compute:

```
RHOAI_CHANNEL = "stable-" + RHOAI_VERSION[0:3]    # e.g., 3.4.2 → stable-3.4
MIRROR_REGISTRY_FQDN = MIRROR_REGISTRY.split(":")[0]  # e.g., bastion.lab
MIRROR_NAMESPACE = "rhoai"                          # default
YOUR_GITOPS_REPO_URL = "https://github.com/" + REPO_OWNER_NAME + ".git"
YOUR_BRANCH = branch name from user
```

### Step 3: Read and Customize Templates

Read each template file from `manifests/disconnected/` and substitute values.

**Phase 1 fills these placeholders:**
- `<OCP_VERSION>` → user's OCP version
- `<RHOAI_VERSION>` → user's RHOAI version
- `<RHOAI_CHANNEL>` → computed channel
- `<MIRROR_REGISTRY>` → user's registry URL
- `<MIRROR_NAMESPACE>` → `rhoai`
- `<MIRROR_REGISTRY_FQDN>` → computed FQDN
- `<YOUR_GITOPS_REPO_URL>` → computed repo URL
- `<YOUR_BRANCH>` → user's branch

**Phase 1 marks these as TODO (not available yet):**
- `<CATALOG_DIGEST>` → replace with `# TODO: Run skopeo inspect to get this digest before mirroring`
- `<CERTIFIED_CATALOG_DIGEST>` → same
- `<MIRRORED_CATALOG_NAME>` → replace with `# TODO: Run 'oc get catalogsource -n openshift-marketplace' after pushing to mirror`
- `<CERTIFIED_CATALOG_NAME>` → same
- `<MIRROR_CA_PEM>` → replace with `# TODO: Paste your mirror registry CA PEM here after installing the mirror registry`

**For the DSC (dsc-v2.yaml):** customize component managementState based on the user's component selection. Set selected components to `Managed`, all others to `Removed`.

### Step 4: Generate README

Generate a `README.md` for the user's repo explaining:
- What this repo deploys
- The two-phase workflow (scaffold now, finalize after mirroring)
- How to run oc-mirror with the ImageSetConfiguration
- How to finalize with Phase 2
- How to apply via ArgoCD (health checks first, then app-of-apps)

### Step 5: Push to Repo

Use `mcp_github.push_files` to push ALL files in a single commit:

```
Commit message: "feat: scaffold RHOAI {VERSION} disconnected deployment for OCP {OCP_VERSION}"
```

Files to push (20 files):

```
README.md
mirror/imageset-config-rhoai.yaml
cluster-config/disable-default-catalogs.yaml
cluster-config/catalog-source-alias.yaml
cluster-config/registry-ca-trust.yaml
cluster-config/pull-secret-patch.sh
cluster-config/kustomization.yaml
operators/cert-manager.yaml
operators/servicemesh3.yaml          # OCP 4.19-4.21 only; omit for 4.22+
operators/nfd.yaml                   # if GPU needed
operators/gpu-operator.yaml          # if GPU needed
operators/rhoai.yaml
operators/kustomization.yaml
rhoai/dsci.yaml
rhoai/dsc-v2.yaml
rhoai/kustomization.yaml
argocd/app-of-apps.yaml
argocd/application-cluster-config.yaml
argocd/application-operators.yaml
argocd/application-rhoai-config.yaml
argocd/argocd-health-checks.yaml
```

### Step 6: Tell User What to Do Next

After pushing, tell the user:

```
Your GitOps repo is scaffolded at https://github.com/{owner}/{name}.

Next steps:
1. On your CONNECTED host, resolve catalog digests:
   skopeo inspect --raw docker://registry.redhat.io/redhat/redhat-operator-index:v{OCP_VERSION} \
     | jq -r '.manifests[] | select(.platform.architecture=="amd64") | .digest'
   
   Edit mirror/imageset-config-rhoai.yaml with the digest.

2. Fetch workbench images:
   curl -sfL https://raw.githubusercontent.com/red-hat-data-services/\
     rhoai-disconnected-install-helper/main/rhoai-{VERSION}.md | ...
   
   Add them to the additionalImages section.

3. Run oc-mirror:
   oc-mirror --v2 --config mirror/imageset-config-rhoai.yaml \
     --image-timeout 60m file:///mnt/mirror/rhoai

4. Install mirror registry, transfer, push to registry.

5. Come back and ask me: "Update my deployment repo with mirror details"
```

---

## Phase 2: Finalize (After Mirroring)

### When to Use

The user has completed mirroring, installed the mirror registry, pushed to the registry, and now has the CatalogSource names and CA PEM.

### Step 1: Gather Remaining Values

Ask the user for:

1. **Mirrored CatalogSource name** — from `oc get catalogsource -n openshift-marketplace` (e.g., `cs-redhat-operator-index-sha256-8d67e`)
2. **Certified CatalogSource name** — for GPU operator (e.g., `cs-certified-operator-index-sha256-ab2ce`)
3. **Mirror registry CA PEM** — the contents of `rootCA.pem` from the mirror registry install
4. **Repo owner/name** — to find the files to update (or remember from Phase 1)

### Step 2: Read Existing Files

Use `mcp_github.get_file_contents` to read the files that have TODO placeholders:
- `operators/cert-manager.yaml`
- `operators/servicemesh3.yaml`
- `operators/nfd.yaml`
- `operators/gpu-operator.yaml`
- `operators/rhoai.yaml`
- `cluster-config/catalog-source-alias.yaml`
- `cluster-config/registry-ca-trust.yaml`
- `rhoai/dsci.yaml`

### Step 3: Replace TODO Placeholders

For each file, replace:
- `# TODO: Run 'oc get catalogsource...'` lines and `<MIRRORED_CATALOG_NAME>` → actual CatalogSource name
- `<CERTIFIED_CATALOG_NAME>` → certified CatalogSource name
- `# TODO: Paste your mirror registry CA PEM...` and `<MIRROR_CA_PEM>` → actual PEM contents

### Step 4: Push Updates

Use `mcp_github.push_files` to push all updated files:

```
Commit message: "feat: finalize deployment repo with mirror registry details"
```

### Step 5: Tell User to Deploy

```
Your repo is ready for deployment.

1. Apply the ArgoCD health checks:
   oc patch argocd openshift-gitops -n openshift-gitops --type merge \
     -p "$(curl -s https://raw.githubusercontent.com/{owner}/{name}/{branch}/argocd/argocd-health-checks.yaml)"

2. Apply IDMS/ITMS/CatalogSources from oc-mirror output:
   oc apply -f <oc-mirror-workspace>/cluster-resources/

3. Apply the app-of-apps:
   oc apply -f - <<EOF
   $(curl -s https://raw.githubusercontent.com/{owner}/{name}/{branch}/argocd/app-of-apps.yaml)
   EOF

4. Monitor in ArgoCD UI or:
   oc get applications -n openshift-gitops -w
```

---

## Output Format

### Phase 1 Output

```
# GitOps Repo Scaffolded

## Repository: {owner}/{name}
## Branch: {branch}
## Commit: {sha}

## Configuration
- OCP Version: {ocp_version}
- RHOAI Version: {rhoai_version}
- Mirror Registry: {registry_url}
- Components: {list of enabled components}

## Files Created: {count}
## TODOs Remaining: 5 (catalog digests, catalog names, CA PEM)

## Next Steps
1. Resolve catalog digests with skopeo
2. Fetch workbench images from helper repo
3. Run oc-mirror
4. Install mirror registry
5. Return for Phase 2: "Update my deployment repo with mirror details"
```

### Phase 2 Output

```
# Deployment Repo Finalized

## Repository: {owner}/{name}
## All TODOs resolved: YES

## Ready to Deploy
1. Apply ArgoCD health checks
2. Apply IDMS/ITMS/CatalogSources
3. Apply app-of-apps
```

---

## Safety Constraints

- **Never push credentials** to the Git repo (no passwords, tokens, or API keys in committed files)
- **Never create the Git repo** — it must already exist. The agent only pushes files.
- **Never apply manifests directly** — the agent generates the files and tells the user how to apply them
- **Always validate the repo exists** before pushing (use `mcp_github.list_branches`)
- **Always use a descriptive commit message** indicating what was scaffolded
- **Always mark unknown values as TODO** rather than guessing or leaving placeholders silently

## Disconnected Environment Notes

This skill is designed primarily for disconnected environments. For connected deployments, the same structure works but `mirror/` and `cluster-config/` directories are not needed — only `operators/`, `rhoai/`, and `argocd/`.

## Related Skills

- [`rhoai-disconnected-deploy`](../rhoai-disconnected-deploy/) — The step-by-step deployment procedure this repo enables
- [`rhoai-connected-deploy`](../rhoai-connected-deploy/) — Connected deployment (simpler, no mirroring)
- [`gitops-config-generator`](../gitops-config-generator/) — Generate additional Kustomize patches
- [`rhoai-install-validator`](../rhoai-install-validator/) — Validate the deployment after applying
