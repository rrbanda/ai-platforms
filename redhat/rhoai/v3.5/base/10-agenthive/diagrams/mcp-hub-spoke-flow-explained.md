# How One MCP Server on Hub Talks to Multiple Spoke Clusters

## Technical Flow Explanation

### The Core Concept

The MCP server does NOT connect directly to spoke clusters. It uses RHACM's **cluster-proxy addon** — a reverse proxy tunnel based on Kubernetes' `apiserver-network-proxy` (konnectivity). Each spoke already maintains a persistent outbound gRPC tunnel back to the hub. The MCP server routes requests through those existing tunnels.

---

## Flow Diagram

```mermaid
sequenceDiagram
    participant Agent as AI Agent<br/>(Claude/Cursor)
    participant GW as MCP Gateway<br/>(Hub - mcp-system ns)
    participant KC as Keycloak<br/>(Hub - OIDC Provider)
    participant MCP as MCP Server<br/>(Hub - openshift-mcp-server ns)
    participant OCM as OCM APIs<br/>(Hub - ManagedCluster CRs)
    participant Proxy as Cluster-Proxy Server<br/>(Hub - multicluster-engine ns)
    participant Agent_Spoke as Cluster-Proxy Agent<br/>(Spoke - outbound tunnel)
    participant API as Spoke kube-apiserver

    Note over Agent,API: STEP 1: Agent sends request
    Agent->>GW: POST /mcp tools/call<br/>"list crashing pods on cluster prod-east"<br/>+ OAuth Bearer Token

    Note over GW,KC: STEP 2: Gateway authenticates
    GW->>KC: Validate JWT signature, expiry, issuer
    KC-->>GW: Token valid ✓
    GW->>GW: Check AuthPolicy - is this user<br/>allowed to call "pods_list" tool?
    GW-->>GW: Tool authorized ✓

    Note over GW,MCP: STEP 3: Gateway forwards to MCP Server
    GW->>MCP: Forward request via HTTPRoute<br/>(backendRef: openshift-mcp-server:8080)

    Note over MCP,OCM: STEP 4: MCP Server identifies target cluster
    MCP->>OCM: list ManagedClusters<br/>(cluster.open-cluster-management.io/v1)
    OCM-->>MCP: Returns cluster inventory<br/>prod-east: Ready, prod-west: Ready, staging: Ready

    Note over MCP,KC: STEP 5: Token exchange for target cluster
    MCP->>KC: RFC 8693 Token Exchange<br/>Exchange broad agent token →<br/>cluster-scoped token for "prod-east"
    KC-->>MCP: Returns scoped access token<br/>(audience: prod-east, limited RBAC)

    Note over MCP,Proxy: STEP 6: MCP Server discovers proxy service
    MCP->>Proxy: Get service "cluster-proxy-addon"<br/>in multicluster-engine namespace
    Proxy-->>MCP: Proxy endpoint:<br/>cluster-proxy-addon.multicluster-engine.svc:8090

    Note over MCP,Agent_Spoke: STEP 7: Route through reverse tunnel
    MCP->>Proxy: Dial via konnectivity-client<br/>Target: prod-east kube-apiserver<br/>+ scoped token
    Proxy->>Agent_Spoke: Route through existing<br/>gRPC reverse tunnel<br/>(spoke initiated this outbound)
    Agent_Spoke->>API: Forward to local kube-apiserver<br/>GET /api/v1/pods?fieldSelector=status.phase!=Running

    Note over API,Agent_Spoke: STEP 8: Spoke responds
    API-->>Agent_Spoke: Pod list response (JSON)
    Agent_Spoke-->>Proxy: Return via tunnel
    Proxy-->>MCP: Response data

    Note over MCP,Agent: STEP 9: MCP Server returns structured response
    MCP-->>GW: MCP tool result<br/>(structured pod data)
    GW-->>Agent: Return to AI agent
    Agent->>Agent: LLM analyzes:<br/>"3 pods in CrashLoopBackOff<br/>in namespace payments..."
```

---

## Bullet Point Flow

### Step 1 — Agent Sends Request
- AI agent (Claude Code, Cursor, etc.) sends MCP tool call to the gateway
- Example: "list all crashing pods on cluster prod-east"
- Request includes an OAuth bearer token from Keycloak/Entra ID

### Step 2 — Gateway Authenticates & Authorizes
- MCP Gateway validates the JWT token (signature, expiry, issuer)
- Kuadrant AuthPolicy checks: is this user allowed to call `pods_list`?
- If unauthorized → 403 Forbidden, request never reaches MCP server
- If authorized → forwards to MCP server

### Step 3 — Gateway Forwards to MCP Server
- Gateway uses the HTTPRoute (in-cluster service reference)
- Routes to `openshift-mcp-server:8080` on the same hub cluster
- This is a local in-cluster hop, not a network call to a remote cluster

### Step 4 — MCP Server Identifies Target Cluster
- MCP server queries `ManagedCluster` CRs on the hub via OCM APIs
- These CRs are maintained by RHACM — every imported cluster has one
- Server finds "prod-east" in the cluster inventory
- No kubeconfig needed — just the cluster name from the CRs

### Step 5 — Token Exchange (RFC 8693)
- MCP server exchanges the agent's broad token for a **cluster-scoped token**
- Calls Keycloak's token exchange endpoint
- Gets back a narrowly-scoped token: audience=prod-east, limited RBAC
- This prevents lateral movement — token only works on the target cluster

### Step 6 — Discover the Proxy Tunnel Endpoint
- MCP server looks up the `cluster-proxy-addon` service
- Located in the `multicluster-engine` namespace on the hub
- This is the hub-side endpoint of all reverse tunnels from spokes
- Endpoint: `cluster-proxy-addon.multicluster-engine.svc:8090`

### Step 7 — Route Through the Reverse Tunnel (THE KEY STEP)
- MCP server uses a **konnectivity client** to dial through the tunnel
- It tells the proxy server: "I want to reach prod-east's kube-apiserver"
- The proxy server finds prod-east's tunnel (already established by the spoke)
- Request flows: MCP Server → Proxy Server → gRPC tunnel → Proxy Agent on spoke → local kube-apiserver
- **The spoke initiated this tunnel outbound** — no inbound firewall rules needed on spoke

### Step 8 — Spoke Responds Normally
- Spoke's kube-apiserver receives a standard authenticated API request
- It validates the scoped token via RBAC (normal Kubernetes auth)
- It doesn't know the request came through a tunnel — it's transparent
- Returns pod list (or whatever was requested)
- Response flows back through the same tunnel

### Step 9 — MCP Server Returns to Agent
- MCP server packages the response as a structured MCP tool result
- Gateway passes it back to the AI agent
- LLM analyzes the data and presents findings to the user

---

## Why No MCP Components on Spokes

| Requirement | How it's satisfied | Deployed by whom? |
|-------------|-------------------|-------------------|
| Network tunnel to hub | cluster-proxy agent (outbound gRPC) | RHACM (automatic on import) |
| Cluster registration | Klusterlet | RHACM (automatic on import) |
| Serve API requests | kube-apiserver | OpenShift (always there) |
| MCP protocol handling | NOT needed on spoke | — |
| MCP gateway | NOT needed on spoke | — |
| Token validation | Standard K8s RBAC on spoke | OpenShift (always there) |

**Bottom line**: Everything the MCP server needs on the spoke is already deployed by RHACM when the cluster was first imported. Zero additional installation.

---

## VPN Analogy

- Hub = VPN concentrator
- Each spoke = VPN client that maintains a persistent tunnel home
- MCP server = application behind the concentrator that can reach any client
- The spoke doesn't know the MCP server exists — it just sees normal API requests arriving through its tunnel

---

## References

- [OCM Cluster Proxy Docs](https://open-cluster-management.io/docs/getting-started/integration/cluster-proxy/)
- [cluster-proxy GitHub](https://github.com/open-cluster-management-io/cluster-proxy)
- [OCP 4.22 MCP Server Docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/ai_applications/mcp-server)
- [MCP Server Blog](https://www.redhat.com/en/blog/model-context-protocol-server-red-hat-openshift-now-available-technology-preview)
- [OCM Architecture](https://open-cluster-management.io/docs/concepts/architecture/)
