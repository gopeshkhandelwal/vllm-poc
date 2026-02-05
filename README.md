# Design Studio Agent

AI-powered design studio with LLM inference and image generation on Intel XPU.

## Services

### vLLM Architect (Port 8000)
OpenAI-compatible LLM API running on Intel XPU.

- **Model**: `Qwen/Qwen3-8B`
- **Endpoint**: `http://localhost:8000/v1`
- **GPU**: GPU0 (Intel XPU via Level Zero)

### ComfyUI Flux (Port 3000)
Image generation service with ComfyUI backend.

### Orchestrator (Port 9000)
LangGraph-based orchestrator connecting LLM and image services.

## Quick Start

```bash
# Start all services
docker compose up -d

# Check vLLM status
curl http://localhost:8000/v1/models

# Check ComfyUI status
curl http://localhost:3000/
```

## Configuration

### vLLM Settings
| Setting | Value |
|---------|-------|
| Model | `Qwen/Qwen3-8B` |
| Context Length | 1024 tokens |
| Precision | BF16 |
| GPU Selection | `ONEAPI_DEVICE_SELECTOR=level_zero:0` |

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
- 24GB+ GPU memory per card