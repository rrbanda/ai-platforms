"""
Per-User OGX Knowledge Filter for Open WebUI.

Intercepts chat messages, uploads user-attached files to a per-user
OGX vector store (RHOAI Milvus-backed), and injects retrieved context
into the query before it reaches the Hermes agent.

Each user gets their own vector store named user_{username} in OGX.
The shared agent corpus (rfp_knowledge_v1) is unaffected -- the agent
queries it independently via its own startup.sh discovery.
"""

from pydantic import BaseModel, Field
import requests
import json
import re


class Filter:
    class Valves(BaseModel):
        OGX_BASE_URL: str = Field(
            default="http://rfp-ogx-service.rfp-agent.svc.cluster.local:8321",
            description="OGX server base URL (no trailing slash)",
        )
        EMBEDDING_MODEL: str = Field(
            default="sentence-transformers/nomic-ai/nomic-embed-text-v1.5",
            description="Embedding model for user vector stores",
        )
        MAX_CHUNKS: int = Field(
            default=5,
            description="Maximum chunks to retrieve from user store",
        )
        CONTEXT_PREFIX: str = Field(
            default="[Retrieved from your personal knowledge base]",
            description="Label prepended to injected context",
        )
        priority: int = Field(
            default=0,
            description="Filter execution priority (lower runs first)",
        )

    def __init__(self):
        self.valves = self.Valves()
        self._user_stores: dict[str, str] = {}

    def _safe_username(self, username: str) -> str:
        return re.sub(r"[^a-zA-Z0-9_]", "_", username).strip("_").lower()

    def _store_name(self, username: str) -> str:
        return f"user_{self._safe_username(username)}"

    def _ogx(self, method: str, path: str, **kwargs) -> requests.Response:
        url = f"{self.valves.OGX_BASE_URL.rstrip('/')}{path}"
        kwargs.setdefault("timeout", 15)
        return getattr(requests, method)(url, **kwargs)

    def _get_or_create_store(self, username: str) -> str:
        if username in self._user_stores:
            return self._user_stores[username]
        name = self._store_name(username)
        try:
            r = self._ogx("get", "/v1/vector_stores")
            if r.ok:
                for s in r.json().get("data", []):
                    if s.get("name") == name:
                        self._user_stores[username] = s["id"]
                        return s["id"]
            r = self._ogx(
                "post",
                "/v1/vector_stores",
                json={
                    "name": name,
                    "provider_id": "milvus",
                    "embedding_model": self.valves.EMBEDDING_MODEL,
                },
            )
            if r.ok:
                store_id = r.json().get("id", "")
                if store_id:
                    self._user_stores[username] = store_id
                return store_id
        except Exception:
            pass
        return ""

    def _upload_and_attach(self, username: str, filename: str, content: str):
        store_id = self._get_or_create_store(username)
        if not store_id:
            return
        try:
            fr = self._ogx(
                "post",
                "/v1/files",
                files={"file": (filename, content.encode("utf-8"), "text/plain")},
                data={"purpose": "assistants"},
                timeout=30,
            )
            if not fr.ok:
                return
            file_id = fr.json().get("id")
            if not file_id:
                return
            self._ogx(
                "post",
                f"/v1/vector_stores/{store_id}/files",
                json={"file_id": file_id},
                timeout=30,
            )
        except Exception:
            pass

    def _query_user_store(self, username: str, query: str) -> list[str]:
        store_id = self._user_stores.get(username)
        if not store_id:
            name = self._store_name(username)
            try:
                r = self._ogx("get", "/v1/vector_stores")
                if r.ok:
                    for s in r.json().get("data", []):
                        if s.get("name") == name:
                            self._user_stores[username] = s["id"]
                            store_id = s["id"]
                            break
            except Exception:
                pass
        if not store_id:
            return []
        try:
            r = self._ogx(
                "post",
                "/v1/vector-io/query",
                json={
                    "query": query,
                    "vector_store_id": store_id,
                    "params": {"max_chunks": self.valves.MAX_CHUNKS},
                },
            )
            if r.ok:
                data = r.json()
                chunks = data.get("chunks", data.get("data", []))
                return [c["content"] for c in chunks if c.get("content")]
        except Exception:
            pass
        return []

    async def inlet(self, body: dict, __user__: dict = None) -> dict:
        if not __user__:
            return body
        username = __user__.get("name", __user__.get("email", "anonymous"))
        messages = body.get("messages", [])
        if not messages:
            return body

        last = messages[-1]
        if last.get("role") != "user":
            return body

        if last.get("files"):
            for f in last["files"]:
                name = f.get("name", "upload.txt")
                content = ""
                data = f.get("data", {})
                if isinstance(data, dict):
                    content = data.get("content", "")
                elif isinstance(data, str):
                    content = data
                if content and len(content) > 10:
                    self._upload_and_attach(username, name, content)

        query = last.get("content", "")
        if query:
            chunks = self._query_user_store(username, query)
            if chunks:
                ctx = "\n---\n".join(chunks)
                last["content"] = (
                    f"{self.valves.CONTEXT_PREFIX}\n{ctx}\n\n{last['content']}"
                )

        return body
