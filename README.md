# Design Studio Agent

AI-powered design studio with LLM inference and image generation on Intel XPU.

## Services

### vLLM Architect (Port 8001)
OpenAI-compatible LLM API running on Intel XPU.

- **Model**: `openai/gpt-oss-20b` (MXFP4 quantized)
- **Endpoint**: `http://localhost:8001/v1`
- **GPU**: Intel Arc Pro B60 (single GPU)

### ComfyUI Flux (Port 3000)
Image generation service with ComfyUI backend.

### Orchestrator (Port 9000)
LangGraph-based orchestrator connecting LLM and image services.

## Quick Start

```bash
# Start all services
docker compose up -d

# Check vLLM status
curl http://localhost:8001/v1/models

# Test chat completion
curl http://localhost:8001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "openai/gpt-oss-20b", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 50}'

# Check ComfyUI status
curl http://localhost:3000/
```

## Configuration

### vLLM Settings
| Setting | Value |
|---------|-------|
| Model | `openai/gpt-oss-20b` |
| Context Length | 4096 tokens |
| Precision | MXFP4 (quantized) |
| GPU Memory | ~10-12GB |

### Model Storage
- vLLM models: `./models/huggingface/`
- ComfyUI models: `./models/comfyui/`

Models are auto-downloaded on first startup.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `HUGGING_FACE_HUB_TOKEN` | HuggingFace token for gated models |
| `MODEL_NAME` | Model name for orchestrator |

## Requirements

- Docker & Docker Compose
- Intel XPU with Level Zero drivers
- 16GB+ GPU memory