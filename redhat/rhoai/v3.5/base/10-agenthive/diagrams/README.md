# Architecture Diagrams

---

## RFP Agent — End-to-End Architecture

The RFP Agent is a Hermes-based AI agent deployed on OpenShift via an AgentHive Sandbox CRD. It uses an 8-skill orchestrated pipeline to process RFP/RFI documents, backed by Gemini 2.5 Pro and RAG retrieval through an OGX (Llama Stack) server with a Milvus vector database.

### System Architecture

Shows all layers: user access, OpenShift ingress, Hermes agent runtime, skill orchestration (8 skills), RAG pipeline, knowledge corpus (33 docs), sandbox security (OpenShell + OPA), evaluation framework (RAGAS + MLflow), and GitOps delivery (ArgoCD + Kustomize).

- Source: [`rfp-agent-architecture.mmd`](rfp-agent-architecture.mmd)
- Rendered: [`rfp-agent-architecture.png`](rfp-agent-architecture.png)

### Skill Pipeline Sequence

Shows the end-to-end RFP processing workflow as a sequence diagram: intake (classify documents) -> analysis (extract requirements) -> strategy (gap analysis via RAG) -> drafting (generate response sections) -> accuracy review (claim-by-claim verification) -> final review (completeness checklist) -> export (DOCX/PDF delivery).

- Source: [`rfp-agent-skill-pipeline.mmd`](rfp-agent-skill-pipeline.mmd)
- Rendered: [`rfp-agent-skill-pipeline.png`](rfp-agent-skill-pipeline.png)

### Rendering

```bash
cd diagrams
npm install
./node_modules/.bin/mmdc -i rfp-agent-architecture.mmd -o rfp-agent-architecture.png -w 2800 -H 3600 -b transparent -s 2
./node_modules/.bin/mmdc -i rfp-agent-skill-pipeline.mmd -o rfp-agent-skill-pipeline.png -w 2800 -H 4800 -b transparent -s 2
```

---

## MCP + RHACM Hub-and-Spoke Architecture

## Architecture Diagram

```mermaid
graph TB
    subgraph AGENTS["AI Agents / MCP Clients"]
        A1["Claude Code / Cursor / VS Code"]
        A2["OpenShift LightSpeed"]
        A3["Custom AI Apps"]
    end

    subgraph HUB["RHACM Hub Cluster"]
        
        subgraph GW_LAYER["MCP Gateway Layer - Red Hat Connectivity Link"]
            GW["MCP Gateway<br/>Envoy-based reverse proxy<br/>ns: mcp-system"]
            AUTH_POL["Kuadrant AuthPolicy<br/>JWT validation<br/>Tool-level authorization"]
            BROKER["MCP Broker Router<br/>Tool aggregation and discovery"]
            MCPSR["MCPServerRegistration CR<br/>+ MCPGatewayExtension CR"]
        end

        subgraph MCP_LAYER["MCP Server for Red Hat OpenShift<br/>Helm chart - ns: openshift-mcp-server"]
            MCP_SRV["MCP Server"]
            TOOLSETS["Toolsets:<br/>core | config | metrics | helm<br/>netedge | ossm | kubevirt | tekton"]
            GUARDRAILS["Security Guardrails:<br/>read_only | denied_resources<br/>disable_destructive | RBAC"]
            OTEL["OpenTelemetry<br/>Metrics + Traces"]
        end

        subgraph IDP["Identity and Token Exchange"]
            KEYCLOAK["Keycloak / Entra ID<br/>OIDC Provider"]
            TOKEN_EX["OAuth2 Token Exchange<br/>RFC 8693<br/>Broad to Cluster-scoped tokens"]
        end

        subgraph ACM["RHACM / Multicluster Engine"]
            MCE_OP["Multicluster Engine<br/>Operator"]
            PROXY_SRV["cluster-proxy-addon<br/>server-side<br/>ns: multicluster-engine"]
            OCM_API["OCM APIs:<br/>ManagedCluster<br/>Placement<br/>ManifestWork<br/>Policy"]
        end

        subgraph OBS["Observability"]
            PROM["Prometheus / Thanos"]
            KIALI["Kiali / ServiceMesh"]
        end
    end

    subgraph SPOKE_1["Spoke Cluster 1<br/>No MCP components installed"]
        KL1["Klusterlet<br/>pre-existing from RHACM"]
        CP1["cluster-proxy agent<br/>pre-existing from RHACM"]
        KAPI1["kube-apiserver"]
        W1["Workloads"]
    end

    subgraph SPOKE_2["Spoke Cluster 2<br/>No MCP components installed"]
        KL2["Klusterlet"]
        CP2["cluster-proxy agent"]
        KAPI2["kube-apiserver"]
        W2["Workloads"]
    end

    subgraph SPOKE_N["Spoke Cluster N<br/>No MCP components installed"]
        KLN["Klusterlet"]
        CPN["cluster-proxy agent"]
        KAPIN["kube-apiserver"]
        WN["Workloads"]
    end

    A1 -->|"HTTPS + OAuth Token"| GW
    A2 -->|"HTTPS + OAuth Token"| GW
    A3 -->|"HTTPS + OAuth Token"| GW

    GW --> AUTH_POL
    AUTH_POL -->|"Validate JWT"| KEYCLOAK
    GW --> BROKER
    BROKER --> MCPSR
    MCPSR -->|"HTTPRoute backendRef"| MCP_SRV

    MCP_SRV --> TOOLSETS
    MCP_SRV --> GUARDRAILS
    MCP_SRV --> OTEL

    MCP_SRV -->|"list/watch ManagedClusters"| OCM_API
    MCP_SRV -->|"Discover cluster-proxy service"| PROXY_SRV

    MCP_SRV -->|"Exchange token for target cluster"| TOKEN_EX
    TOKEN_EX --> KEYCLOAK

    MCP_SRV -->|"PromQL queries"| PROM
    MCP_SRV -->|"Mesh health"| KIALI
    OTEL --> PROM

    PROXY_SRV -->|"L4 reverse tunnel"| CP1
    PROXY_SRV -->|"L4 reverse tunnel"| CP2
    PROXY_SRV -->|"L4 reverse tunnel"| CPN

    CP1 --> KAPI1
    CP2 --> KAPI2
    CPN --> KAPIN

    KAPI1 --> W1
    KAPI2 --> W2
    KAPIN --> WN

    KL1 -.->|"Registration"| MCE_OP
    KL2 -.->|"Registration"| MCE_OP
    KLN -.->|"Registration"| MCE_OP
```

## Key Points

| Layer | Hub Cluster | Spoke Clusters |
|-------|-------------|----------------|
| Agent Traffic | MCP Gateway (auth, rate limit, tool filtering) | Nothing |
| MCP Logic | MCP Server (tools, config, RBAC) | Nothing |
| Identity | Keycloak / Entra ID + Token Exchange | Nothing |
| Cluster Mgmt | RHACM + MCE + Cluster-Proxy (server) | Klusterlet + Cluster-Proxy agent (pre-existing) |
| Observability | Prometheus, Thanos, OpenTelemetry | Nothing new |

## References

- [MCP Server for OpenShift - OCP 4.22 Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/ai_applications/mcp-server)
- [MCP Gateway Install - Connectivity Link 1.3](https://docs.redhat.com/en/documentation/red_hat_connectivity_link/1.3/html/installing_the_mcp_gateway/mcp-gateway-install)
- [OpenShift MCP Server GitHub](https://github.com/openshift/openshift-mcp-server)
- [MCP Server Blog Post](https://www.redhat.com/en/blog/model-context-protocol-server-red-hat-openshift-now-available-technology-preview)
