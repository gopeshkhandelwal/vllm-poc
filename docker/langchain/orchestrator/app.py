from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import httpx
import os
import asyncio
from typing import TypedDict

from langgraph.graph import StateGraph, END

app = FastAPI()

VLLM_URL = os.getenv("VLLM_URL")  # may be None; resolve at startup
COMFYUI_URL = os.getenv("COMFYUI_URL", "http://comfyui:8188")
MODEL_NAME = os.getenv(
    "MODEL_NAME",
    "mistralai/Mistral-Large-3-675B-Instruct-2512",
)

# -----------------------------
# Request models
# -----------------------------
class WorkflowRequest(BaseModel):
    prompt: str


class LangChainRequest(BaseModel):
    input: str


# -----------------------------
# Startup: wait for dependencies
# -----------------------------
@app.on_event("startup")
async def wait_for_dependencies():
    global VLLM_URL

    candidates = []
    if VLLM_URL:
        candidates.append(VLLM_URL)

    candidates.extend(
        [
            "http://host.docker.internal:8000",
            "http://172.17.0.1:8000",
            "http://127.0.0.1:8000",
            "http://localhost:8000",
        ]
    )

    resolved = None
    timeout = 60
    interval = 2
    elapsed = 0

    async with httpx.AsyncClient(timeout=3.0) as client:
        while elapsed < timeout and not resolved:
            for candidate in candidates:
                try:
                    r = await client.get(f"{candidate}/health")
                    if r.status_code == 200:
                        resolved = candidate
                        break
                except Exception:
                    continue

            if resolved:
                break

            await asyncio.sleep(interval)
            elapsed += interval

    if resolved:
        VLLM_URL = resolved
        print(f"Orchestrator: resolved vLLM URL -> {VLLM_URL}")
    else:
        if os.getenv("VLLM_URL"):
            VLLM_URL = os.getenv("VLLM_URL")
            print(f"Orchestrator: using VLLM_URL from env -> {VLLM_URL}")
        else:
            print(
                "Warning: could not auto-resolve vLLM host; "
                "set VLLM_URL env to host-accessible address"
            )


# -----------------------------
# Health
# -----------------------------
@app.get("/health")
async def health():
    return {"status": "ok"}

# -----------------------------
# Self-test
# -----------------------------
@app.get("/selftest")
async def selftest():
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            ping = await client.get(f"{VLLM_URL}/health")
        except Exception as e:
            raise HTTPException(
                status_code=502,
                detail=f"vLLM health check failed: {e}",
            )

        if ping.status_code != 200:
            raise HTTPException(
                status_code=502,
                detail=f"vLLM unhealthy: {ping.status_code}",
            )

        r = await client.post(
            f"{VLLM_URL}/v1/completions",
            json={"model": MODEL_NAME, "prompt": "Health check ping"},
        )

        if r.status_code != 200:
            raise HTTPException(
                status_code=502,
                detail=f"vLLM completions failed: {r.status_code}",
            )

        return {
            "status": "ok",
            "vllm_sample": r.json()
            .get("choices", [{}])[0]
            .get("text"),
        }


# =====================================================
# LangGraph: Architect → Reviewer
# =====================================================

class GraphState(TypedDict):
    input: str
    architect_output: str
    reviewer_output: str


async def architect_node(state: GraphState) -> dict:
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            f"{VLLM_URL}/v1/completions",
            json={
                "model": MODEL_NAME,
                "prompt": f"Architect: {state['input']}",
            },
        )

        if resp.status_code != 200:
            raise RuntimeError(
                f"Architect failed: {resp.status_code} {resp.text}"
            )

        j = resp.json()
        choices = j.get("choices") or []
        text = (
            choices[0].get("text")
            if choices
            else j.get("text")
        )

        return {"architect_output": text}


async def reviewer_node(state: GraphState) -> dict:
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            f"{VLLM_URL}/v1/completions",
            json={
                "model": MODEL_NAME,
                "prompt": (
                    "Reviewer: review and improve the following output:\n\n"
                    f"{state['architect_output']}"
                ),
            },
        )

        if resp.status_code != 200:
            raise RuntimeError(
                f"Reviewer failed: {resp.status_code} {resp.text}"
            )

        j = resp.json()
        choices = j.get("choices") or []
        text = (
            choices[0].get("text")
            if choices
            else j.get("text")
        )

        return {"reviewer_output": text}


graph_builder = StateGraph(GraphState)
graph_builder.add_node("architect", architect_node)
graph_builder.add_node("reviewer", reviewer_node)
graph_builder.set_entry_point("architect")
graph_builder.add_edge("architect", "reviewer")
graph_builder.add_edge("reviewer", END)

graph = graph_builder.compile()


@app.post("/graph/run")
async def run_langgraph(req: WorkflowRequest):
    try:
        result = await graph.ainvoke(
            {"input": req.prompt}
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=str(e),
        )

    return {
        "architect": result.get("architect_output"),
        "reviewer": result.get("reviewer_output"),
    }

