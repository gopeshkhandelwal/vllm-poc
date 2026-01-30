from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import httpx
import os
import asyncio

app = FastAPI()
VLLM_URL = os.getenv("VLLM_URL")  # may be None; resolve at startup
COMFYUI_URL = os.getenv("COMFYUI_URL", "http://comfyui:8188")
MODEL_NAME = os.getenv("MODEL_NAME", "mistralai/Mistral-Large-3-675B-Instruct-2512")

class WorkflowRequest(BaseModel):
    prompt: str

class LangChainRequest(BaseModel):
    input: str

@app.on_event("startup")
async def wait_for_dependencies():
    global VLLM_URL
    # Resolve VLLM URL: prefer env var, else try common host addresses so orchestrator can reach a vLLM
    candidates = []
    if VLLM_URL:
        candidates.append(VLLM_URL)
    # Common Docker host addresses (Docker Desktop / Linux docker bridge)
    candidates.extend([
        "http://host.docker.internal:8000",
        "http://172.17.0.1:8000",
        "http://127.0.0.1:8000",
        "http://localhost:8000",
    ])

    resolved = None
    timeout = 60
    interval = 2
    elapsed = 0
    async with httpx.AsyncClient(timeout=3.0) as client:
        # Try to find a reachable vLLM health endpoint within timeout
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
        # fallback to env var if set, else warn; requests will likely fail until user sets VLLM_URL
        if os.getenv("VLLM_URL"):
            VLLM_URL = os.getenv("VLLM_URL")
            print(f"Orchestrator: using VLLM_URL from env -> {VLLM_URL}")
        else:
            print("Warning: could not auto-resolve vLLM host; set VLLM_URL env to host-accessible address (e.g. http://host.docker.internal:8000)")

@app.get("/health")
async def health():
    return {"status": "ok"}

@app.post("/run")
async def run_workflow(req: WorkflowRequest):
    async with httpx.AsyncClient(timeout=30.0) as client:
        # Architect step
        try:
            arch_resp = await client.post(f"{VLLM_URL}/v1/completions", json={"model": MODEL_NAME, "prompt": f"Architect: {req.prompt}"})
        except httpx.RequestError as e:
            raise HTTPException(status_code=502, detail=f"Architect request failed: {e}")

        if arch_resp.status_code != 200:
            raise HTTPException(status_code=502, detail=f"Architect failed: {arch_resp.status_code} {arch_resp.text}")
        arch_json = arch_resp.json()
        arch_choices = arch_json.get("choices") or []
        arch_text = arch_choices[0].get("text") if arch_choices else arch_json.get("text")

        # Reviewer step uses same vLLM
        try:
            rev_resp = await client.post(f"{VLLM_URL}/v1/completions", json={"model": MODEL_NAME, "prompt": f"Reviewer: review the architect output:\n{arch_text}"})
        except httpx.RequestError as e:
            raise HTTPException(status_code=502, detail=f"Reviewer request failed: {e}")

        if rev_resp.status_code != 200:
            raise HTTPException(status_code=502, detail=f"Reviewer failed: {rev_resp.status_code} {rev_resp.text}")
        rev_json = rev_resp.json()
        rev_choices = rev_json.get("choices") or []
        rev_text = rev_choices[0].get("text") if rev_choices else rev_json.get("text")

    return {"architect": arch_text, "reviewer": rev_text}

@app.post("/langchain")
async def langchain_invoke(req: LangChainRequest):
    """
    Simple endpoint to be used by LangChain or other tools.
    Expects JSON {"input": "..."} and forwards to single vLLM endpoint.
    Returns {"text": "..."}.
    """
    async with httpx.AsyncClient(timeout=30.0) as client:
        try:
            resp = await client.post(f"{VLLM_URL}/v1/completions", json={"model": MODEL_NAME, "prompt": req.input})
        except httpx.RequestError as e:
            raise HTTPException(status_code=502, detail=f"vLLM request failed: {e}")

        if resp.status_code != 200:
            raise HTTPException(status_code=502, detail=f"vLLM returned {resp.status_code}: {resp.text}")
        j = resp.json()
        choices = j.get("choices") or []
        text = choices[0].get("text") if choices else j.get("text")
        return {"text": text}

@app.get("/selftest")
async def selftest():
    """Trigger a test Architect->Reviewer flow internally to verify connectivity."""
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            ping = await client.get(f"{VLLM_URL}/health")
        except Exception as e:
            raise HTTPException(status_code=502, detail=f"vLLM health check failed: {e}")
        if ping.status_code != 200:
            raise HTTPException(status_code=502, detail=f"vLLM unhealthy: {ping.status_code}")

        # run tiny flow
        r = await client.post(f"{VLLM_URL}/v1/completions", json={"model": MODEL_NAME, "prompt": "Health check: ping"})
        if r.status_code != 200:
            raise HTTPException(status_code=502, detail=f"vLLM completions failed: {r.status_code}")
        return {"status": "ok", "vllm_sample": r.json().get("choices")[0].get("text")}

